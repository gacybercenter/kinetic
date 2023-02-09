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

def merge_tables(current_tables, 
                    new_tables, 
                    get_difference=False):
    merged_tables = {'netgate-nat:mapping-table': {'mapping-entry': []}}
    # Loop through the current tables
    for table in current_tables['netgate-nat:mapping-table']['mapping-entry']:
        if get_difference:
            # Append tables in current tables, but not in new tables
            if table not in new_tables['netgate-nat:mapping-table']['mapping-entry']:
                merged_tables['netgate-nat:mapping-table']['mapping-entry'].append(table)
        else:
            # Append tables in current tables, but not in merged_tables
            if table not in merged_tables['netgate-nat:mapping-table']['mapping-entry']:
                merged_tables['netgate-nat:mapping-table']['mapping-entry'].append(table)
    # Loop through the new tables
    for table in new_tables['netgate-nat:mapping-table']['mapping-entry']:
        if not get_difference:
            # Append tables in new tables, but not in merged_tables
            if table not in merged_tables['netgate-nat:mapping-table']['mapping-entry']:
                merged_tables['netgate-nat:mapping-table']['mapping-entry'].append(table)

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

def merge_zones(current_zones, 
                new_zones, 
                get_difference=False):
    merged_zones = {'netgate-unbound:local-zones': {'zone': []}}
    # Loop through the current tables
    for zone in current_zones['netgate-unbound:local-zones']['zone']:
        if get_difference:
            # Append tables in current tables, but not in new tables
            if zone not in new_zones['netgate-unbound:local-zones']['zone']:
                merged_zones['netgate-unbound:local-zoneses']['zone'].append(zone)
        else:
            # Append tables in current tables, but not in merged_tables
            if zone not in merged_zones['netgate-unbound:local-zones']['zone']:
                merged_zones['netgate-unbound:local-zones']['zone'].append(zone)
    # Loop through the new tables
    for zone in new_zones['netgate-unbound:local-zones']['zone']:
        if not get_difference:
            # Append tables in new tables, but not in merged_tables
            if zone not in merged_zones['netgate-unbound:local-zones']['zone']:
                merged_zones['netgate-unbound:local-zones']['zone'].append(zone)

    return merged_zones