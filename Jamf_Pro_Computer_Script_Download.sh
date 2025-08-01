#!/bin/bash

# This script is designed to use the Jamf Pro API to identify the individual IDs of 
# the scripts stored on a Jamf Pro server then do the following:
#
# 1. Download the script as XML
# 2. Identify the script name
# 3. Extract the script contents from the downloaded XML
# 4. Save the script to a specified directory

# If setting up a specific user account with limited rights, here are the required API privileges
# for the account on the Jamf Pro server:
#
# Jamf Pro Server Objects:
#
# Scripts: Read

# If you choose to specify a directory to save the downloaded scripts into,
# please specify your computer hostname and enter the complete directory path
# into the ScriptDownloadDirectory variable below.

hostname=$(/usr/sbin/scutil --get HostName)
case $hostname in
     HOSTNAME1.local)
          ScriptDownloadDirectory="/Users/<username>/CodeProjects/jamf-scripts/jamf-scripts"
          ;;
    HOSTNAME2.local)
          ScriptDownloadDirectory="/Users/<username>/Code Projects/jamf-scripts/jamf-scripts"
          ;;

     *)
          # If the ScriptDownloadDirectory isn't specified above, a temporary directory will be
          # created and the complete directory path displayed by the script.
          ScriptDownloadDirectory=$(mktemp -d)
          echo "A location to store downloaded scripts has not been specified."
          echo "Downloaded scripts will be stored in $ScriptDownloadDirectory."
          ;;
esac


# This script is explicitly for use by techs, so we're going to go ahead and hard-code
# the Jamf API credentials into the script. Remove any of these lines to force the script
# to prompt you for the Jamf Pro API client credentials that are not present.
jamfpro_url="https://your.jamf.url:port/"	
apiClientID="[Jamf API Client ID Here]"
apiClientSecret="[Jamf API Client Secret Here]"


# If the Jamf Pro URL, the API Client ID or the Client secret aren't available
# otherwise, you will be prompted to enter the requested URL or account credentials.

if [[ -z "$jamfpro_url" ]]; then
     read -p "Please enter your Jamf Pro server URL : " jamfpro_url
fi

if [[ -z "$apiClientID" ]]; then
     read -p "Please enter your Jamf Pro API Client ID : " apiClientID
fi

if [[ -z "$apiClientSecret" ]]; then
     read -p "Please enter the API Client Secret for the API Client with ID: $apiClientID : " -s apiClientSecret
fi

echo ""


# Remove the trailing slash from the Jamf Pro URL if needed.
jamfpro_url=${jamfpro_url%%/}

# Remove the trailing slash from the ScriptDownloadDirectory variable if needed.
ScriptDownloadDirectory=${ScriptDownloadDirectory%%/}


#### Block below is the framework for connecting to JAMF API ####

json_value() { # Version 2023.3.4-1 - Copyright (c) 2023 Pico Mitchell - MIT License - Full license and help info at https://randomapplications.com/json_value
	{ set -- "$(/usr/bin/osascript -l 'JavaScript' -e 'ObjC.import("unistd"); function run(argv) { const stdin = $.NSFileHandle.fileHandleWithStandardInput; let out; for (let i = 0;' \
		-e 'i < 3; i ++) { let json = (i === 0 ? argv[0] : (i === 1 ? argv[argv.length - 1] : ($.isatty(0) ? "" : $.NSString.alloc.initWithDataEncoding((stdin.respondsToSelector("re"' \
		-e '+ "adDataToEndOfFileAndReturnError:") ? stdin.readDataToEndOfFileAndReturnError(ObjC.wrap()) : stdin.readDataToEndOfFile), $.NSUTF8StringEncoding).js.replace(/\n$/, ""))))' \
		-e 'if ($.NSFileManager.defaultManager.fileExistsAtPath(json)) json = $.NSString.stringWithContentsOfFileEncodingError(json, $.NSUTF8StringEncoding, ObjC.wrap()).js; if (/[{[]/' \
		-e '.test(json)) try { out = JSON.parse(json); (i === 0 ? argv.shift() : (i === 1 && argv.pop())); break } catch (e) {} } if (out === undefined) throw "Failed to parse JSON."' \
		-e 'argv.forEach(key => { out = (Array.isArray(out) ? (/^-?\d+$/.test(key) ? (key = +key, out[key < 0 ? (out.length + key) : key]) : (key === "=" ? out.length : undefined)) :' \
		-e '(out instanceof Object ? out[key] : undefined)); if (out === undefined) throw "Failed to retrieve key/index: " + key }); return (out instanceof Object ? JSON.stringify(' \
		-e 'out, null, 2) : out) }' -- "$@" 2>&1 >&3)"; } 3>&1; [ "${1##* }" != '(-2700)' ] || { set -- "json_value ERROR${1#*Error}"; >&2 printf '%s\n' "${1% *}"; false; }
}

getAccessToken() {
	response=$(curl --silent --location --request POST "${jamfpro_url}/api/oauth/token" \
 	 	--header "Content-Type: application/x-www-form-urlencoded" \
 		--data-urlencode "client_id=${apiClientID}" \
 		--data-urlencode "grant_type=client_credentials" \
 		--data-urlencode "client_secret=${apiClientSecret}")
 	access_token=$(echo "$response" | plutil -extract access_token raw -)
 	token_expires_in=$(echo "$response" | plutil -extract expires_in raw -)
 	token_expiration_epoch=$(($current_epoch + $token_expires_in - 1))
}

checkTokenExpiration() {
	current_epoch=$(date +%s)
    if [[ $token_expiration_epoch -ge $current_epoch ]]; then
		a=0 
		echo "Token valid until the following epoch time: " "$token_expiration_epoch"
    else
        echo "No valid token available, getting new token"
        getAccessToken
    fi
}

invalidateToken() {
	responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${access_token}" $jamfpro_url/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
	if [[ ${responseCode} == 204 ]]; then
		# echo "Token successfully invalidated"
		access_token=""
		token_expiration_epoch="0"
	elif [[ ${responseCode} == 401 ]]; then
		a=0 # echo "Token already invalid"
	else
		a=0 # echo "An unknown error occurred invalidating the token"
	fi
}


echo "Getting list of scripts from ${jamfpro_url}"
checkTokenExpiration

Script_id_list=$(curl -ks -X 'GET' \
     "${jamfpro_url}/api/v1/scripts?page=0&page-size=10000&sort=name%3Aasc" \
     -H "Accept: application/json" \
     -H "Authorization: Bearer $access_token" 2>/dev/null)
#echo "$Script_id_list"


Script_id_count=$( echo "${Script_id_list}" | json_value 'totalCount' )
#echo "$Script_id_count"

for ((count=0; count<"$Script_id_count"; count++)); do
	ScriptName=$( echo "${Script_id_list}" | json_value 'results' $count 'name' )
	#echo "ScriptName: ${ScriptName}"

	ScriptContents=$( echo "${Script_id_list}" | json_value 'results' $count 'scriptContents' )
	#echo "ScriptContents: ${ScriptContents}"

	## Save the downloaded script 
#	echo "${ScriptName}       - Script being downloaded."
	echo "Saving ${ScriptName} file to $ScriptDownloadDirectory."

	echo "$ScriptContents" | sed -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e 's/&amp;/\&/g' > "$ScriptDownloadDirectory/${ScriptName}"
	# Add in that pesky missing line return at the end of the file.
	# echo "" >> "$ScriptDownloadDirectory/${ScriptName}"
done

invalidateToken
exit 0
