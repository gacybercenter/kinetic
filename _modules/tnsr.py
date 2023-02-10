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

def nat_entries_request(method,
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

def merge_entries(current_entries, new_entries, get_difference=False):
    # Initialize the dictionary that will store the merged entries
    merged_entries = {'netgate-nat:mapping-table': {'mapping-entry': []}}
    # Extract entries from their wrappers
    current_entries = current_entries['netgate-nat:mapping-table']['mapping-entry']
    new_entries = new_entries['netgate-nat:mapping-table']['mapping-entry']
    # If get_difference is True, return current entries - new entries
    if get_difference:
        different = [entry for entry in current_entries if entry not in new_entries]
        merged_entries['netgate-nat:mapping-table']['mapping-entry'] = different
    # If get_difference is False, return current entries + new entries
    else:
        same = [entry for entry in new_entries if entry not in current_entries]
        same += current_entries
        merged_entries['netgate-nat:mapping-table']['mapping-entry'] = same
    # Return the merged entries
    return merged_entries

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
    # Extract zones from their wrappers
    current_zones = current_zones['netgate-unbound:local-zones']['zone']
    new_zones = new_zones['netgate-unbound:local-zones']['zone']
    # If get_difference is True, return current zones - new zones
    if get_difference:
        different = [entry for entry in current_zones if entry not in new_zones]
        merged_zones['netgate-unbound:local-zones']['zone'] = different
    # If get_difference is False, return current zones + new zones
    else:
        same = [entry for entry in new_zones if entry not in current_zones]
        same += current_zones
        merged_zones['netgate-unbound:local-zones']['zone'] = same
    # Return the merged zones
    return merged_zones
