#!/bin/zsh --no-rcs

#####################################################################################
#
# MaxonInstallApp.zsh
#
####################################################################################
#
# HISTORY
#
#   Version 1.1.0, 2025-07-30, John Bowman (MacAdmins Slack @JOHNb)
#   - v0.0.3 - Original Version
#   - v1.0.0 - Updated installer method for Red Giant Universe
#   - v1.1.0 - Updated installer method for Red Giant\
#
####################################################################################
# A script to install a specific app from the Maxon One app library                #
#                                                                                  #
# Note:                                                                            #
#   Assumes Maxon.app and AutoLogin command for Maxon.app are installed per:	   #
#	   https://support.maxon.net/hc/en-us/articles/5178815935644-How-to-set-up-the-Maxon-App-for-Automatic-Logins #
#   Make sure path to mk1 and AutoLogin commands are properly specified in script  #
#   Must be run with escalated privileges                                          #
#                                                                                  #
# Usage:                                                                           #
#   1) Get list of available apps to install by running                            #
#      /Library/Application\ Support/Maxon/Tools/mx1 product list                  #
#      while logged into mx1/Maxon.app                                             #
#        Available packages:                                                       #
#           net.maxon.cinema4d                                                     #
#           net.maxon.teamrender                                                   #
#           net.maxon.zbrush                                                       #
#           com.redgiant.magicbullet                                               #
#           com.redgiant.shooter.pluraleyes                                        #
#           com.redgiant.trapcode                                                  #
#           com.redgiant.universe                                                  #
#           com.redgiant.vfx                                                       #
#           com.redshift3d.redshift                                                #
#   2) Select an app identifier from the package you wish to install               #
#      i.e. - com.redgiant.trapcode to install the Red Giant Trapcode package      #
#   3) Determine if you wish to install specific version or latest available.      #
#      Consult https://www.maxon.net/en/downloads for listing of available         #
#      downloads by version number.                                                #
#   4) Run script via Jamf Pro, populating the parameters as designated.           #
#      Alternately run from the command line like this -                           #
#        MaxonInstallApp.zsh 1 2 3 [app identifier] [app version to install]       #
#                                                                                  #
####################################################################################

maxonToolsPath="/Library/Application Support/Maxon/Tools"

### Specify path to mx1 command ###
mx1app="${maxonToolsPath}/mx1"

### Specify path to AutoLogin command ###
autoLoginCommand="${maxonToolsPath}/MaxonAppLogin.command"

### Specify AutoLogin username ###
autoLoginUser="maca_maxon@macomb.edu"

############## DO NOT EDIT BELOW THIS LINE ##############

# Read in command line parameters from Jamf Pro (Parameters 1-3 are predefined)
appIdentifier="${4}"        # Parameter 4: Specify identifier from app to be installed.
appVersion="${5}"           # Parameter 5: Specify version of app to install. Will install latest available version if left blank.

# Create placeholders for working folder, installer zip, and installer app
workingFolder="/private/tmp/MaxonTempInstaller_$( date +%Y-%m-%d_%H:%M:%S )"
installerDownload=""
installerType=""
installerApp=""

runScript () {
    verifyLoggedIn
    validateAppName
    createTempFolder
    downloadInstaller
    getInstallerType
    if [[ "${installerType}" == "zip" ]]; then
        unzipInstaller
    elif [[ "${installerType}" == "dmg" ]]; then
        undmgInstaller
    elif [[ "${installerType}" == "pkg" ]]; then
        # Package is ready to go as downloaded
        installerApp="${installerDownload}"
    else
        echo "Unknown installer type '${installerType}'. Exiting..."
        exit 1
    fi
    if [[ "${installerApp:0:6}" == "ZBrush" ]]; then
        uninstallOldZBrush
    fi
    installApp
    removeTempFolder
}


function verifyLoggedIn() {
    echo "Testing if user '${autoLoginUser}' is already logged in..."

    testUser=$(/usr/bin/sudo -u root "${mx1app}" user info | awk '/user/ { print $2; }')
    if [[ "${testUser}" == "${autoLoginUser}" ]]; then
        echo "User '${autoLoginUser}' already logged in."
    else
        echo "User '${autoLoginUser}' not logged in. Logging in now..."
        /usr/bin/sudo -u root "${autoLoginCommand}"
    fi
}

function validateAppName() {
    echo "Testing if app '${appIdentifier}' is available..."
    testAppMultiline=$(/usr/bin/sudo -u root "${mx1app}" product list | awk "/${appIdentifier} / { print \$NF; }")
    testApp=$(echo "${testAppMultiline}" | head -1)
    if [[ "${testApp}" == "${appIdentifier}" ]]; then
        echo "Identifier '${appIdentifier}' is available. Proceeding with install..."
    else
        echo "Identifier '${appIdentifier}' not found. Exiting..."
        exit 1
    fi

}

function createTempFolder() {
    echo "Creating the temporary folder at ${workingFolder}..."
    mkdir -p "${workingFolder}"
    chmod 777 "${workingFolder}"
}

function downloadInstaller() {
    cd "${workingFolder}"
    if [[ "${appVersion}" == "" ]]; then
        echo "Downloading latest version of package that contains '${appIdentifier}'..."
        /usr/bin/sudo -u root "${mx1app}" package download "${appIdentifier}" &> /dev/null
    else
        echo "Downloading v${appVersion} of package that contains '${appIdentifier}'..."
        /usr/bin/sudo -u root "${mx1app}" package download "${appIdentifier}" "${appVersion}" &> /dev/null
    fi
    installerDownload=$(ls "${workingFolder}")

    if [[ "${installerDownload}" == "" ]]; then
        echo "No installer downloaded to ${workingFolder}. Exiting..."
        exit 1
    else
        echo "${installerDownload} downloaded to ${workingFolder}."
    fi
}

function getInstallerType() {
    echo "Determining installer type of '${installerDownload}'..."
    installerType="${installerDownload:(-3)}"
    echo "'${installerDownload}' appears to be a '${installerType}' installer."
}

function unzipInstaller() {
    echo "Unzipping ${installerDownload}..."
    unzip "${installerDownload}" &> /dev/null

    echo "Deleting ${installerDownload}..."
    rm -f "${installerDownload}"

    installerApp=$(ls "${workingFolder}")

    if [[ "${installerApp}" == "" ]]; then
        echo "No app installer unzipped to ${workingFolder}. Exiting..."
        exit 1
    else
        echo "'${installerApp}' unzipped into ${workingFolder}."
    fi
}

function undmgInstaller() {
    echo "Extracting installer from ${installerDownload}..."
    echo "Mounting ${installerDownload}..."
    mountedDMG=$(hdiutil attach ${installerDownload} | awk 'BEGIN {FS="\t"}; /Volumes/  { print $NF }')
    mountedDMGinstaller=$(ls "${mountedDMG}" | grep 'Installer')

    echo "copying '${mountedDMGinstaller}' from  ${mountedDMG} to ${workingFolder}..."
    cp -R "${mountedDMG}/${mountedDMGinstaller}" ./

    echo "Unmounting ${installerDownload}..."
    hdiutil detach "${mountedDMG}" &> /dev/null

    echo "Deleting ${installerDownload}..."
    rm -f "${installerDownload}"

    installerApp=$(ls "${workingFolder}")

    if [[ "${installerApp}" == "" ]]; then
        echo "No app installer extracted to ${workingFolder}. Exiting..."
        exit 1
    else
        echo "'${installerApp}' extracted into ${workingFolder}."
    fi
}

function uninstallOldZBrush(){
    # See if old version of ZBrush is installed and if so uninstall it before doing install.
    # (Zbrush automated installer has a bad habit of popping up an authentication dialog for
    # the uninstaller if there is an existing install of ZBrush.)
    existingZBrushFolder=$(ls /Applications | grep 'ZBrush')
    if [[ "${existingZBrushFolder}" == "" ]]; then
        echo "No previous version of ZBrush found."
    else
        echo "Previous version of ZBrush found in /Applications/${existingZBrushFolder}. Removing now..."
        "/Applications/${existingZBrushFolder}/Uninstall/Uninstall Maxon ZBrush.app/Contents/MacOS/installbuilder.sh" \
            --mode unattended --unattendedmodeui none
    fi
}

function installApp() {
    if [[ "${appVersion}" == "" ]]; then
        echo "Performing silent install of latest version of '${installerApp}'..."
    else
        echo "Performing silent install of v${appVersion} of '${installerApp}'..."
    fi

    if [[ "${installerApp:0:6}" == "ZBrush" ]] ||
        [[ "${installerApp:0:9}" == "Red Giant" ]] ||
        [[ "${installerApp:0:8}" == "Universe" ]] ||
        [[ "${installerApp:0:15}" == "Maxon Cinema 4D" ]]; then
        # Install method for ZBrush and Cinema 4D
        "${workingFolder}/${installerApp}/Contents/MacOS/installbuilder.sh" --mode unattended --unattendedmodeui none
    elif [[ "${installerType}" == "pkg" ]]; then
        # Install method for Redshift (.pkg downloads)
        /usr/sbin/installer -pkg "${workingFolder}/${installerApp}" -target /
    else
        # Install method for Red Giant (.zip downloads)
        "${workingFolder}/${installerApp}/Contents/Scripts/install.sh"
    fi
}

function removeTempFolder() {
    echo "Removing the temporary folder and exiting..."
    rm -rf "${workingFolder}"
}


runScript

exit 0
