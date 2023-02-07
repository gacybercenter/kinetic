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

## tnsr module - helper functions for tnsr state module
## could potentially be fleshed out and become formal fully-featured
## salt module

# import urllib3
# import base64

# urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

import requests

__virtualname__ = 'tnsr'

def __virtual__():
    return __virtualname__

### NAT SECTION ###

def nat_tables_request(method, 
                    cert, 
                    key, 
                    cacert=False, 
                    payload=None,
                    hostname="https://tnsr.internal.gacyberrange.org",
                    headers={'Content-Type': 'application/yang-data+json'}):
    url = f"{hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table"
    response = requests.request(method, 
                                url, 
                                cert=(cert, key), 
                                verify=cacert, 
                                headers=headers, 
                                data=payload)
    return response.text

### UNBOUND SECTION ###

def unbound_zones_request(method, 
                        cert, 
                        key, 
                        cacert=False,
                        payload=None, 
                        hostname="https://tnsr.internal.gacyberrange.org",
                        headers={'Content-Type': 'application/yang-data+json'}):
    url = f"{hostname}/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones"
    response = requests.request(method, 
                                url, 
                                cert=(cert, key), 
                                verify=cacert, 
                                headers=headers, 
                                data=payload)
    return response.text

