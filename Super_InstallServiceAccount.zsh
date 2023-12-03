#!/bin/zsh

#####################################################################################
#
# Super_InstallServiceAccount.zsh - 
#   Install S.U.P.E.R.M.A.N. Service Account from macOSLAPS
#
####################################################################################
#
# HISTORY
#
#   Version 0.0.4, 2023-11-27, John Bowman (MacAdmins Slack @JOHNb)
#   - Original Version
#
####################################################################################
# A script that uses the macOSLAPS account to install the super service account    #
#                                                                                  #
# NOTE: You MUST exclude the characters "[", "]", "=", and "$" from your macOSLAPS #
#   password to prevent the password from hanging up the super script.             #
####################################################################################

# Read in command line parameters from Jamf Pro (Parameters 1-3 are predefined)
macOSLAPSaccount="${4}"        # Parameter 4: Specify the account used for macOSLAPS

# Create placeholder for macOSLAPS Password
macOSLAPSpassword=""

# Specify macOSLAPS password file location
macOSLAPSpasswordFile="/var/root/Library/Application Support/macOSLAPS-password"


runScript () {
    getmacOSLAPSpassword
    createSuperServiceAccount
    remove_macOSLAPSpasswordFile
}


function getmacOSLAPSpassword() {
    echo "Getting the macOSLAPS password..."
    /usr/local/laps/macoslaps -getPassword
    macOSLAPSpassword=$(cat "${macOSLAPSpasswordFile}")
}

function createSuperServiceAccount() {
    echo "Creating the 'super' service account used by the S.U.P.E.R.M.A.N. workflow..."

    /usr/local/bin/super --auth-service-add-via-admin-account=$macOSLAPSaccount \
	  --auth-service-add-via-admin-password=${macOSLAPSpassword} --reset-super \
  	  --workflow-disable-update-check --workflow-disable-relaunch --verbose-mode-off
      # Previous line disables update checks and relaunch of super script - 
	  # I'm JUST installing the service account here, not trying to launch a workflow.
      # Feel free to modify these parameters if your workflow calls for it.

      # But leave verbose mode off unless you want your macOSLAPS password to 
      # be output in plaintext to the Jamf Pro policy log.
}

function remove_macOSLAPSpasswordFile() {
    echo "Removing the generated macOSLAPS password file and exiting..."
    rm -f "${macOSLAPSpasswordFile}"
}


runScript

exit 0
