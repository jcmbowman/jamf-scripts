#!/bin/zsh --no-rcs

:<<ABOUT_THIS_SCRIPT
-------------------------------------------------------------------------------

	Written by: John Bowman
	Apple Support Specialist
	Macomb Community College
	jcmbowman@gmail.com

	Originally created: 2025-07-29

	Purpose:
    When a designated user is created, run jamf recon, then trigger a
    specified Jamf policy .

    In our use case we will use a Jamf Pro policy to trigger the SetupYourMac
    workflow, but only if the designated LAPS account has been created on the
    local computer.

    This script is designed to flexible enough to use in other applications.

    Reason:
    Currently the Jamf Managed Local Administrator account is not being
    created during enrollment, but it will be created once a user logs in to
    the computer. This only works if no other processes are being run by the
    Jamf binary.

	The launch daemon and script are necessary because we want to fire off
    the SYM workflow as soon as the LAPS account has been created, but we
    don't want the Jamf binary to be occupied, thus blocking the creation
    of the Managed Local Administrator account.

	Instructions:

	1. Create a new script in Jamf Pro named something like
        "TriggerPolicyIfAccountExists.zsh".

	   Paste the entire contents of this script as-is into the Script field.

	   Under the Options tab, set the following parameter labels.
	   Parameter 4: Jamf Policy custom trigger (e.g., "symStart")
	   Parameter 5: Account to wait for (e.g., "jamfadmin")
	   Parameter 6: Organization Reverse Domain (e.g., "com.example")

	3. Create a smart computer group named something like:
	   "Recently Enrolled Computers"

	   Set its criteria to:
	   "Last Enrollment" - "less than x days ago" - "1".

	4. Add the script to a new policy named something like
       "Setup Your Mac - trigger if 'jamfadmin' exists".

	   Set the four script parameters:
       Jamf Policy custom trigger (e.g., "symStart")
       Jamf Managed LAPS account name (e.g., "jamfadmin")
	   Organization Reverse Domain (e.g., "com.example")

	   Enable the policy to trigger at Login with a frequency of
	   Once Per Computer.

	   Scope the policy:
	   Set Target to "Recently Enrolled Computers"

	After a computer is logged into and completes the policy, the
    LaunchDaemon will check every 15 seconds for up to 15 minutes to see if
    the designated account exists on the local computer.

    The script has also been configured such that you can simply hard-code
    your parameters and not bother setting them in the policy.

	(Note: This script has borrowed heavily from William Smith's
        'Re-enroll computers for LAPS.zsh' script, which can be found here:
    	https://gist.github.com/talkingmoose/9f4638932df28c4bebde5dd47be1812a)

	Except where otherwise noted, this work is licensed under
	http://creativecommons.org/licenses/by/4.0/.

	"Someone will solve a problem, if he finds the problem interesting."
	— Tim O'Reilly

-------------------------------------------------------------------------------
ABOUT_THIS_SCRIPT


# script parameters from the Jamf Pro policy
policyToTrigger="${4:-"symStart"}"
accountToCheck="${5:-"cadmin"}"
organizationReverseDomain="${6:-"edu.macomb"}"


# Global Variables
scriptFolder="/Library/Management/$organizationReverseDomain.trigger-$policyToTrigger"
scriptName="trigger-$policyToTrigger.zsh"
plistName="$organizationReverseDomain.trigger-$policyToTrigger.plist"

runScript () {
    createTriggerPolicyScript
    createLaunchDaemon
    loadLaunchDaemon
}


createTriggerPolicyScript() {
    # create organization folder if necessary to house the script
    /bin/mkdir -p "${scriptFolder}"

    # create trigger-<policyToTrigger>.zsh script
    tee "${scriptFolder}/$scriptName" << EOF
#!/bin/zsh --no-rcs

runScript () {
    waitUntilUserExists "${accountToCheck}"
    triggerJamfRecon
    triggerJamfPolicy "${policyToTrigger}"
    cleanUpScript
}

checkIfUserExists() {
    User="\${1}"
    local UserExists=false

    testUser=\$( id "\${User}" 2>&1 )
    if [[ "\${testUser}" == "id: \${User}: no such user" ]]; then
        a=0
    else
        UserExists=true
    fi
	echo "\${UserExists}"
}

waitUntilUserExists () {
    User="\${1}"
    count=0
    userExists=\$( checkIfUserExists "\${User}" )
    until \$userExists; do
        sleep 15
        ((count++))
        if [[ \$count -gt 60 ]]; then
            exit 1
        fi
    done
}

triggerJamfRecon() {
    /usr/bin/sudo /usr/local/bin/jamf recon > /dev/null 2>&1
}

triggerJamfPolicy() {
    policy="\${1}"
    # Fire off the Jamf policy using detached execution.
    /usr/bin/nohup /usr/bin/sudo /usr/local/bin/jamf policy -trigger "\${policy}" > /dev/null 2>&1 &
}

cleanUpScript() {
    # delete this script
    /bin/rm "${scriptFolder}/$scriptName"

    # attempt to delete enclosing directory
    /bin/rmdir "${scriptFolder}"

    # delete the launch daemon plist
    /bin/rm "/Library/LaunchDaemons/$plistName"

    # kill the launch daemon process
    /bin/launchctl remove "$organizationReverseDomain.trigger-$policyToTrigger"
}

runScript
exit 0
EOF

    # set correct ownership and permissions on trigger-<policyToTrigger>.zsh script
    /usr/sbin/chown root:wheel "${scriptFolder}/$scriptName" && /bin/chmod +x "${scriptFolder}/$scriptName"

}

createLaunchDaemon() {
    # create $$organizationReverseDomain.trigger-$policyToTrigger.plist launch daemon

    tee /Library/LaunchDaemons/$plistName << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key>
		<string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
	</dict>
	<key>Label</key>
	<string>$organizationReverseDomain.trigger-$policyToTrigger</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/zsh</string>
		<string>-c</string>
		<string>"${scriptFolder}/$scriptName"</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF

    # set correct ownership and permissions on launch daemon
    /usr/sbin/chown root:wheel /Library/LaunchDaemons/$plistName && /bin/chmod 644 /Library/LaunchDaemons/$plistName

}

loadLaunchDaemon() {
    # start launch daemon after installation
    /bin/launchctl bootstrap system /Library/LaunchDaemons/$plistName && /bin/launchctl start /Library/LaunchDaemons/$plistName
}

runScript
exit 0
