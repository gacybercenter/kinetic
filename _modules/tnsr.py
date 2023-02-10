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

def merge_tables(current_tables, new_tables, get_difference=False):
    # Initialize the dictionary that will store the merged zones
    merged_tables = {'netgate-nat:mapping-table': {'mapping-entry': []}}    
    # If get_difference is True, return only the zones that are in current_zones but not in new_zones
    if get_difference:
        merged_tables['netgate-nat:mapping-table']['mapping-entry'] = [table for table in current_tables['netgate-nat:mapping-table']['mapping-entry'] 
                                                                    if table not in new_tables['netgate-nat:mapping-table']['mapping-entry']]
    # If get_difference is False, merge the two lists of zones
    else:
        merged_tables['netgate-nat:mapping-table']['mapping-entry'] = [table for table in new_tables['netgate-nat:mapping-table']['mapping-entry'] 
                                                                    if table not in current_tables['netgate-nat:mapping-table']['mapping-entry']]
        merged_tables['netgate-nat:mapping-table']['mapping-entry'] += current_tables['netgate-nat:mapping-table']['mapping-entry']
    
    # Return the merged zones
    return merged_tables

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

def merge_zones(current_zones, new_zones, get_difference=False):
    # Initialize the dictionary that will store the merged zones
    merged_zones = {'netgate-unbound:local-zones': {'zone': []}}
    
    # If get_difference is True, return only the zones that are in current_zones but not in new_zones
    if get_difference:
        merged_zones['netgate-unbound:local-zones']['zone'] = [zone for zone in current_zones['netgate-unbound:local-zones']['zone'] 
                                                            if zone not in new_zones['netgate-unbound:local-zones']['zone']]
    # If get_difference is False, merge the two lists of zones
    else:
        merged_zones['netgate-unbound:local-zones']['zone'] = [zone for zone in new_zones['netgate-unbound:local-zones']['zone'] 
                                                            if zone not in current_zones['netgate-unbound:local-zones']['zone']]
        merged_zones['netgate-unbound:local-zones']['zone'] += current_zones['netgate-unbound:local-zones']['zone']
    
    # Return the merged zones
    return merged_zones
