#!/usr/bin/env python3

####
#
# SetRecoveryLockJAMF.py
#
# Created 2022-12-14 by John Bowman
#
# Script to set recovery lock for macOS computers in JAMF Pro
#
# Adapted from https://github.com/shbedev/jamf-recovery-lock
#
####

### User-edited Variables ###
# Define how we connect to JAMF
jamf_url            = 'jamf.myorg.edu:8443'
jamf_api_username   = 'jamf_api'
jamf_api_password   = 'ApiPasswordGoesHere' 

########## DO NOT EDIT BELOW THIS LINE ##########
import argparse, sys

# Initialize command line argument parser
parser = argparse.ArgumentParser()
 
# Adding command line arguments
parser.add_argument(
    "SearchString",
    help = "String to use to search JAMF computer names"
)
group = parser.add_mutually_exclusive_group()
group.add_argument(
    "-p", "--Passcode", 
    help = "Specify Recovery Lock passcode (default is blank)"
)
group.add_argument(
    "-r", "--RandomPasscode", nargs='?', const=20,
    help = "Generate a different random Recovery Lock passcode for each computer (default length is 20, specify a value for a different length)"
)

 
# Read arguments from command line
args = parser.parse_args()
 

### From git project auth/basic_auth.py
import base64
def auth_token():
    # create base64 encoded string of jamf API user credetinals
    credentials_str = f'{jamf_api_username}:{jamf_api_password}'
    data_bytes = credentials_str.encode("utf-8")
    encoded_bytes = base64.b64encode(data_bytes)
    encoded_str = encoded_bytes.decode("utf-8")

    return encoded_str


### From git project auth/bearer_auth.py
import os, time, requests
# current working directory
cwd = os.path.dirname(os.path.realpath(__file__))

# path of token file in current working directory
token_file = f'{cwd}/token.txt'

def request_token():
    """Generate an auth token from API"""
    
    headers = {
        'Accept': 'application/json',
        'Authorization': f'Basic {auth_token()}',
        'Content-Type': 'application/json',
    } 

    try:
        response = requests.request("POST", f'https://{jamf_url}/api/v1/auth/token', headers=headers)
        response.raise_for_status()

    except requests.exceptions.HTTPError as err:
        raise SystemExit(err)

    return response.json()['token']

def get_token():
    """Returns a token from local cache or API request"""
    current_time = int(time.time())

    # check if token is cached and if it is less than 30 minutes old
    if os.path.exists(token_file) and ((current_time - 1800) < os.stat(token_file)[-1]):
        # return a cached token from file
        return read_token_from_local()
    else:
        # return a token from API
        return get_token_from_api()

def get_token_from_api():
    """Returns a token from an API request"""
    token = request_token()
    cache_token(token)
    return token

def cache_token(token):
    """
    Cache token to local file
    Parameters:
        token - str
    """
    with open(token_file, 'w') as file_obj:
        file_obj.write(token)

def read_token_from_local():
    """Read cached token from local file"""
    with open(token_file, 'r') as file_obj:
        token = file_obj.read().strip()
    return token


### From git project computers.py
import requests
import math

headers = {
    'Accept': 'application/json',
    'Authorization': f'Bearer {get_token()}',
    'Content-Type': 'application/json',
}

def get_computer_count():
    """
    Returns the number of computers in Jamf Pro
    """

    try:
        response = requests.get(
            url=f'https://{jamf_url}/api/v1/computers-inventory?section=HARDWARE&page=0&page-size=1&sort=id%3Aasc',
            headers=headers
        )
        response.raise_for_status()
    
    except requests.exceptions.HTTPError as err:
        raise SystemExit(err)

    count = response.json()['totalCount']
    #print("Number of computers in JAMF = " + str(count))

    return count

computers_per_page = 1000
number_of_pages = math.ceil(get_computer_count() / computers_per_page)

def get_arm64(filter = None):
    """
    Returns Jamf IDs of all arm64 type computers
    
    Parameters:
        filter - (e.g. 'filter=general.name=="jdoe-mbp"'). If empty, returns all computers.
        Computer name in filter is not case sensitive 
    """

    computers_id = []

    for pageIndex in range(number_of_pages):

        try:
            response = requests.get(
                url=f'https://{jamf_url}/api/v1/computers-inventory?section=HARDWARE&page={pageIndex}&page-size={computers_per_page}&sort=id%3Aasc&{filter}',
                headers=headers
            )
            response.raise_for_status()
        
        except requests.exceptions.HTTPError as err:
            raise SystemExit(err)

        computers = response.json()['results']

        for computer in computers:
            if computer['hardware']['processorArchitecture'] == 'arm64':
                computers_id.append(computer['id'])

    if computers_id == []:
        sys.exit("No Apple Silicon computers found in Jamf that match search string.")  

    return computers_id
    


def get_mgmt_id(computers_id):
    """
    Returns Jamf computers management id
    
    Parameters:
        computers_id - (e.g. ['10', '12']]). List of Jamf computers id 
    """
    computers_mgmt_id = []

    for pageIndex in range(number_of_pages):
        try:
            response = requests.get(
                url = f'https://{jamf_url}/api/preview/computers?page={pageIndex}&page-size={computers_per_page}&sort=name%3Aasc',
                headers=headers
            )
            response.raise_for_status()
            
        except requests.exceptions.HTTPError as err:
            raise SystemExit(err)

        computers = response.json()['results']

        for computer_id in computers_id:
            for computer in computers:
                # Find computers that given computer id in list of computers
                if computer['id'] == computer_id:
                    computer_mgmt_id = computer['managementId']
                    computer_name = computer['name']
                    # Add computer to list
                    computers_mgmt_id.append({
                        'id': computer_id,
                        'name': computer_name,
                        'mgmt_id': computer_mgmt_id
                    })
                    break

    return computers_mgmt_id



### From git project recovery_lock.py
import requests

headers = {
    'Accept': 'application/json',
    'Authorization': f'Bearer {get_token()}',
    'Content-Type': 'application/json',
}

def set_key(computer_name, management_id, recovery_lock_key):
    """Sets a Recovery Lock key for a given computer"""
    
    print(f'Settings recovery lock key: {recovery_lock_key} for {computer_name}')

    payload = {
        'clientData': [
            {
            'managementId': f'{management_id}',
            'clientType': 'COMPUTER'
            }
        ],
        'commandData': {
            'commandType': 'SET_RECOVERY_LOCK',
            'newPassword': f'{recovery_lock_key}'
        }
    }

    try:
        response = requests.request("POST", f'https://{instance_id}/api/preview/mdm/commands', headers=headers, json=payload)

        response.raise_for_status()
        
    except requests.exceptions.HTTPError as err:
        raise SystemExit(err)



### From git project main.py
from random import randint

computers_id = get_arm64('filter=general.name=="*'+args.SearchString+'*"')
computers_mgmt_id = get_mgmt_id(computers_id)


print("These are the changes you will be making:")

for computer in computers_mgmt_id:  
    computer_name = computer['name']
    computer_mgmt_id = computer['mgmt_id']
    if args.Passcode:
        print("   "+computer_name+" will have its Recovery Lock set to "+args.Passcode)
    elif args.RandomPasscode:
        print("   "+computer_name+" will have its Recovery Lock set to a random "+str(args.RandomPasscode)+"-digit number")
    else:
        print("   "+computer_name+" will have its Recovery Lock cleared")
    

print("")
go_ahead = input("Do you wish to proceed? (y/n)")
print("")

if go_ahead == ("y" or "Y"):
    for computer in computers_mgmt_id:
        computer_name = computer['name']
        computer_mgmt_id = computer['mgmt_id']
        if args.Passcode:
            recovery_lock_key = args.Passcode
            print("   Command sent for "+computer_name+" Recovery Lock to be set to "+str(recovery_lock_key))
        elif args.RandomPasscode:
            rand_low_val=pow(10,(int(args.RandomPasscode) - 1))
            rand_val_high=pow(10,int(args.RandomPasscode)) - 1
            recovery_lock_key = randint(rand_low_val,rand_val_high)
            print("   Command sent for "+computer_name+" Recovery Lock to be set to "+str(recovery_lock_key))
        else:
            recovery_lock_key = ''
            print("      Command sent to clear Recovery Lock on "+computer_name)

    
        set_key(computer_name, computer_mgmt_id, recovery_lock_key)
    print("")
