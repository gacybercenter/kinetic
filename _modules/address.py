## Copyright 2020 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

## module for IP address management
## interfaces with simlpe sqlite3 database in order to obviate the
## issue of dhcp relay/calculated addresses
## includes functions focused on creating leases as well
## as functions focused on getting those leases issued to clients
## in a usable format


import json
import logging
import os
import requests
import sqlite3

log = logging.getLogger(__name__)

__virtualname__ = 'address'

def __virtual__():
    return __virtualname__

def rest_login(username, password, url):
    try:
        login = requests.post(
                    f'https://{url}:8000/login',
                    verify=False,
                    json={
                        'username':username,
                        'password':password,
                        'eauth':'pam'
                    }
                )
        token = json.loads(login.text)["return"][0]["token"]
        return token
    except Exception as e:
        log.error("Unable to authenticate foruse %s: %s", username, e)
        return False

# NOTE(chateaulav): this function needs to be refactored to be single focused
def client_get_address(username, password, network, host, url, target):
    try:
        token = rest_login(username, password, url)
        lease = requests.post(
                    f'https://{url}:8000/',
                    verify=False,
                    headers={
                        'X-Auth-Token':token
                    },
                    json=[
                        {
                        'client': 'local',
                        'tgt': target,
                        'fun': 'address.get_address',
                        'arg': [network, host]
                        }
                    ]
                )
        address = json.loads(lease.text)["return"][0][target]
        return address
    except Exception as e:
        log.error("Unable to execute: %s", e)
        return False
