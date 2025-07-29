#!/bin/zsh --no-rcs

#####################################################################################
#
# Super_InstallServiceAccount.zsh -
#   Install S.U.P.E.R.M.A.N. Service Account from Jamf API LAPS
#
####################################################################################
#
# HISTORY
#
#   Version 1.0.1, 2025-05-12, John Bowman (MacAdmins Slack @JOHNb)
#   - 0.0.4 - Original Version (macOSLAPS)
#   - 1.0.1 - Jamf API LAPS version
#
####################################################################################
# A script that uses a Jamf API LAPS account to install the super service account  #
####################################################################################

### User Editable Variables:
jamfBaseURL="https://jamf.macomb.edu:8443"  # Your Jamf URL, with the https://
script_name="Super_InstallServiceAccount"



### Jamf Parameters - You can hard-code the credentials into this script, but I don't advise it.
# Jamf Parameter 4 should contain the Managed Local Administrator account.
if [ "$4" != "" ]; then lapsAdmin=$4
else echo "[${script_name}] No Managed Local Administrator account supplied. Exiting."; exit 1; fi

# Jamf Parameter 5 should contain a Jamf API Client ID.
if [ "$5" != "" ]; then JamfApiClientID=$5
else echo "[${script_name}] No Jamf API Client ID supplied. Exiting."; exit 1; fi

# Jamf Parameter 6 should contain the Jamf API Client's Secret.
if [ "$6" != "" ]; then JamfApiClientSecret=$6
else echo "[${script_name}] No Jamf API Client Secret supplied. Exiting."; exit 1; fi

# Get computer architecture
ComputerArch=$(uname -m)





runScript () {
    verifyLapsAdminVolumeOwner
    getJamfManagementID
    getLapsAdminPasswordViaJamfAPI
    createSuperServiceAccount
}



#### Block below is the framework for authenticating to JAMF API and getting auth token ####
jamfAccessToken=""
jamfTokenExpirationEpoch=0
jamfManagementID=""
lapsAdminPassword=""

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
	local current_epoch=$(date +%s)
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


verifyLapsAdminVolumeOwner () {
    lapsAdminStatus=$(sysadminctl -secureTokenStatus $lapsAdmin 2>&1 | grep -e "Secure token is ENABLED")
	if [[ "$lapsAdminStatus" == "" ]]; then
        echo "[$script_name] User '$lapsAdmin' not a volume owner. Exiting with error."
		exit 1
	fi
	echo "[$script_name] User '$lapsAdmin' validated as a volume owner. Proceeding."
}


getJamfManagementID () {
    checkJamfTokenExpiration
    serialNumber=$(system_profiler SPHardwareDataType | grep Serial | awk '{print $NF}')

	jamfManagementID=$(curl -ks \
        "$jamfBaseURL/api/v1/computers-inventory?section=GENERAL&page=0&page-size=100&sort=&filter=hardware.serialNumber%3D%3D%22$serialNumber%22" \
        -H "Authorization: Bearer ${jamfAccessToken}" | jq -r '.results.[0].general.managementId')
	if [[ "$jamfManagementID" == "" ]]; then
        echo "[$script_name] Unable to locate a computer in JAMF with this serial number. How is this script even running?"
		exit 1
	fi
	echo "[$script_name] Found JAMF management ID of $jamfManagementID"
}


getLapsAdminPasswordViaJamfAPI () {
    checkJamfTokenExpiration
	lapsAdminPassword=$(curl -ks \
        "$jamfBaseURL/api/v2/local-admin-password/$jamfManagementID/account/$lapsAdmin/password" \
        -H "Authorization: Bearer ${jamfAccessToken}" | jq -r '.password')
	if [[ "$lapsAdminPassword" == "" ]]; then
        echo "[$script_name] Unable to locate LAPS password for user '$lapsAdmin'. Exiting with error."
		exit 1
	fi
	echo "[$script_name] Found LAPS password for user '$lapsAdmin'"
}


function createSuperServiceAccount() {
    echo "Creating the 'super' service account used by the S.U.P.E.R.M.A.N. workflow..."

    /usr/local/bin/super --auth-service-add-via-admin-account=$lapsAdmin \
	  --auth-service-add-via-admin-password=${lapsAdminPassword} --reset-super \
  	  --workflow-disable-update-check --workflow-disable-relaunch --verbose-mode-off
      # Previous line disables update checks and relaunch of super script -
	  # I'm JUST installing the service account here, not trying to launch a workflow.
      # Feel free to modify these parameters if your workflow calls for it.

      # But leave verbose mode off unless you want your macOSLAPS password to
      # be output in plaintext to the Jamf Pro policy log.
}


runScript
invalidateJamfToken
exit 0
