#!/bin/zsh -x
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2296
# these are due to the dynamic variable assignments used in the localization strings

: <<DOC
erase-install-launcher-wJamfAPIAuth.sh - 

HISTORY
    Version 0.0.1, 2025-04-24, John Bowman (MacAdmins Slack @JOHNb)
    - Original Version

Adapted from https://github.com/grahampugh/erase-install/blob/main/erase-install-launcher.sh

This script is designed to be used as a stub for launching erase-install.sh when
deploying the standard macOS package of erase-install from within Jamf Pro.

You can simply add this script to the "Scripts" section of a Jamf Pro policy,
which will in turn launch erase-install.sh with all supplied parameters and
return its output and return code back to Jamf Pro. If the computer 
architecture is Apple Silicon it will attempt to use he Jamf API to acquire 
Jamf LAPS credentials to authenticate the script.

You must use Jamf Pro parameter 4 to supply the Jamf managed local administrator
account username.

Parameters 5 and 6 are for supplying a Jamf API Client ID and Jamf API Client Secret.
This API Client should be assigned a role that grants coumper info lookup and
view local admin password privileges.

You can use Jamf Pro parameters 7-10 to supply arguments to erase-install,
and you can supply multiple arguments in one Jamf Pro parameter.

The last parameter can be used to specify the location of erase-install.sh, if
you have deployed a custom version of erase-install at a different location.

KNOWN LIMITATION
Don't add a parameter after a parameter with a value within a single Parameter field in Jamf.
e.g. don't add something like "--os 13 --erase" in the same box.
Parameters without values are ok to put in a single Parameter field in Jamf.
e.g. this is OK: "--erase --reinstall --confirm"

DOC

### User Editable Variables:
jamfBaseURL="https://jamf.yourdomain.edu:8443"  # Your Jamf URL, with the https://

script_name="erase-install-launcher-wjamfapiauth"



### Jamf Parameters - You can hard-code the credentials into this script, but I don't advise it.
# Parameter 4 should contain a Jamf managed local administrator account.
if [ "$4" != "" ]; then localAdmin=$4
else echo "No managed local administrator account supplied. Exiting."; exit 1; fi

# Parameter 5 should contain a Jamf API Client ID.
if [ "$5" != "" ]; then JamfApiClientID=$5
else echo "No Jamf API Client ID supplied. Exiting."; exit 1; fi

# Parameter 6 should contain the Jamf API Client's Secret.
if [ "$6" != "" ]; then JamfApiClientSecret=$6
else echo "No Jamf API Client Secret supplied. Exiting."; exit 1; fi

# Parameters 7-10 are handled below and may contain erase-install parameters

# Parameter 11 may contain an alternate erase-install script path.
# If parameter is not supplied it will default to the default installation location.
eraseinstall_path="${11:-"/Library/Management/erase-install/erase-install.sh"}"


echo
echo "[$script_name] Launching ${eraseinstall_path} using the following arguments:"

escape_args() {
    temp_string=$(awk 'BEGIN{FS=OFS="\""} {for (i=1;i<=NF;i+=2) gsub(/ /,"§",$i)}1' <<< "$1")
    # temp_string=$(awk -F\" '{OFS="\""; for(i=2;i<NF;i+=2)gsub(/ /,"++",$i);print}' <<< "$1")
    temp_string="${temp_string//\\ /++}"
    echo "$temp_string"
}

arguments=()
count=1
for i in {7..10}; do
    # first of all we replace all spaces with a § symbol
    eval_string="${(P)i}"
    parsed_parameter="$(escape_args "$eval_string")"

    # now we have split up the parameter we can put the spaces back
    for p in $parsed_parameter; do
        arguments+=("${p//§/ }")
    done
done

eraseinstall_args=()
for arg in "${arguments[@]}"; do
    if [[ "$arg" == "--"* ]]; then
        # replace any equals after the command with a space
        arg="${arg/=/ }"
        # if the first argument is an option (--*) then any second part should be a value, split it once more
        first_arg=$(cut -d' ' -f1 <<< "$arg")
        if [[ "$first_arg" ]]; then
            eraseinstall_args+=("$first_arg")
            echo "[$count] $first_arg"
            ((count++))
            potential_arg=$(cut -d' ' -f2- <<< "$arg")
            if [[ "$potential_arg" && ("$potential_arg" != "$first_arg") ]]; then
                eraseinstall_args+=("$potential_arg")
                echo "[$count] $potential_arg"
                ((count++))
            fi
        fi
    else
        eraseinstall_args+=("$arg")
        echo "[$count] $arg"
        ((count++))
    fi
done


#### Block below is the framework for authenticating to JAMF API and getting auth token ####
jamfAccessToken=""
jamfTokenExpirationEpoch=0

getJamfAccessToken() {
	response=$(curl --silent --location --request POST "${jamfBaseURL}/api/oauth/token" \
 	 	--header "Content-Type: application/x-www-form-urlencoded" \
 		--data-urlencode "client_id=${JamfApiClientID}" \
 		--data-urlencode "grant_type=client_credentials" \
 		--data-urlencode "client_secret=${JamfApiClientSecret}")
 	jamfAccessToken=$(echo "$response" | plutil -extract access_token raw -)
 	token_expires_in=$(echo "$response" | plutil -extract expires_in raw -)
 	jamfTokenExpirationEpoch=$(($current_epoch + $token_expires_in - 1))
}

checkJamfTokenExpiration() {
	current_epoch=$(date +%s)
    if [[ $jamfTokenExpirationEpoch -ge $current_epoch ]]; then
		a=0 #echo "Token valid until the following epoch time: " "$jamfTokenExpirationEpoch"
    else
        #echo "No valid token available, getting new token"
        getJamfAccessToken
    fi
}

invalidateJamfToken() {
	responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${jamfAccessToken}" $jamfBaseURL/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
	if [[ ${responseCode} == 204 ]]; then
		# echo "Token successfully invalidated"
		jamfAccessToken=""
		jamfTokenExpirationEpoch=0
	elif [[ ${responseCode} == 401 ]]; then
		a=0 # echo "Token already invalid"
	else
		a=0 # echo "An unknown error occurred invalidating the token"
	fi
}

getJamfManagementID () {
    serialNumber=$(system_profiler SPHardwareDataType | grep Serial | awk '{print $NF}')
    checkJamfTokenExpiration
	jamfManagementID=$(curl -ks \
        "$jamfBaseURL/api/v1/computers-inventory?section=GENERAL&page=0&page-size=100&sort=&filter=hardware.serialNumber%3D%3D%22$serialNumber%22" \
        -H "Authorization: Bearer ${jamfAccessToken}" | jq -r '.results.[].general.managementId')
	if [[ "$jamfManagementID" == "" ]]; then
        echo "[$script_name] Unable to locate a computer in JAMF with this serial number. How is this script even running?"
		exit 1
	fi
	echo "[$script_name] Found JAMF management ID of $jamfManagementID"	
}


# Create global variables
localAdminPass=""
localAdminCreds=""
jamfManagementID=""


function getlocalAdminPass() {
    echo "[$script_name] Getting the local administrator password via Jamf LAPS."
    getJamfManagementID

    checkJamfTokenExpiration
	localAdminPass=$(curl -ks \
        "$jamfBaseURL/api/v2/local-admin-password/$jamfManagementID/account/$localAdmin/password" \
        -H "Authorization: Bearer ${jamfAccessToken}" | jq -r '.password')
	if [[ "$localAdminPass" == "" ]]; then
        echo "[$script_name] Unable to locate password for user '$localAdmin'. Exiting with error."
		exit 1
	fi
	echo "[$script_name] Found password for user '$localAdmin' - '$localAdminPass'"	

}

function encodelocalAdminCreds() {
    echo "[$script_name] Encoding the local admin Credentials..."
    localAdminCreds=$(printf "%s:%s" "${localAdmin}" "${localAdminPass}" | iconv -t ISO-8859-1 | base64 -i -)
}


# Get computer architecture
ComputerArch=$(uname -m)
if [[ "${ComputerArch}" == "arm64" ]]; then
    echo
    echo "[$script_name] Computer architecture is Apple Silicon. Getting local admin credentials."
    getlocalAdminPass
    encodelocalAdminCreds
    eraseinstall_args+=("--very-insecure-mode")
    eraseinstall_args+=("--credentials")
    eraseinstall_args+=("${localAdminCreds}")
fi

echo

"${eraseinstall_path}" "${eraseinstall_args[@]}"
# echo "${eraseinstall_path} ${eraseinstall_args[@]}"


rc=$?

echo
echo "[$script_name] Exit ($rc)"
exit $rc
