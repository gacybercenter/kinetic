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

### Tnsr State Module

import json
import yaml

__virtualname__ = 'tnsr'

def __virtual__():
    return __virtualname__

def nat_updated(name,
                new_entries,
                cert,
                key,
                cacert=False,
                **kwargs):
    """
    Manages NAT entry entries.

    This state module compares the current NAT entries for the inputed entries.
    It calls out to the execution modules 'merge_entries' and 'nat_entries_request'
    to get and combine the new entries with the current entries. It if the new
    entries don't exist in the current entries, it calls out to the execution
    module 'nat_entries_request' in order to update the current NAT entries to
    the combined new and current entries. This state module can also test for
    changes by setting "test" keyword argument to true. Finally, this state module
    can delete the new entries fron the current NAT entries by setting "delete"
    keyword argument to true.

    name
        Name of Salt state
    new_entries
        NAT entries to be added or removed
    cert
        Path to certificate location
    key
        Path to key location
    hostname
        Host device URL
    cacert : False
        Path to certificate authority location
    **kwargs
        test : False
            When True, returns results without making changes to the NAT table
        delete : False
            When True, deletes new entries from the current NAT table
    """
    # Checks for "test" and "delete" keyword arguments, default to False if not provided
    test = kwargs.get("test", __opts__.get("test", False))
    remove = kwargs.get("delete", __opts__.get("remove", False))

    ret = {
        "name": name,
        "changes": {},
        "result": True,
        "comment": ""
    }
    # Get current NAT entries
    current_entries = __salt__["tnsr.nat_entries_request"]("GET",
                                                            cert,
                                                            key,
                                                            cacert=cacert)

    # Parse current JSON and new YAML data
    current_entries = json.loads(current_entries)
    new_entries = {'netgate-nat:mapping-table': {'mapping-entry': yaml.safe_load(new_entries)}}

    merged_entries = __salt__["tnsr.merge_entries"](current_entries,
                                                    new_entries,
                                                    remove)

    # If item to be removed does not exist
    if remove and merged_entries == current_entries:
        ret["comment"] = "NAT entries to be removed do not exist"
        return ret

    # If item to be added already exists
    if not remove and merged_entries == current_entries:
        ret["comment"] = "NAT entries to be added already exist"
        return ret

    # If test, return old and new entries
    if test:
        ret["changes"] = {
            "old": current_entries,
            "new": merged_entries,
        }
        ret["comment"] = "NAT entries would have been updated"
        ret["result"] = None
        return ret

    # Update NAT mapping entries
    __salt__["tnsr.nat_entries_request"]("PUT",
                                        cert,
                                        key,
                                        cacert=cacert,
                                        payload=json.dumps(merged_entries))

    # Return successful update
    ret["changes"] = {
            "old": current_entries,
            "new": merged_entries,
        }
    ret["comment"] = "Successfully updated NAT entries"
    ret["result"] = True
    return ret

def unbound_updated(name,
                    new_zones,
                    cert,
                    key,
                    cacert=False,
                    **kwargs):
    """
    Manages Unbound zones.

    This state module compares the current Unbound zones for the inputed zones.
    It calls out to the execution modules 'merge_zones' and 'unbound_zones_request
    to get and combine the new zones with the current Unbound zones. It if the new
    zones don't exist in the current Unbound zones, it calls out to the execution
    module 'unbound_zones_request' in order to update the current Unbound zones to
    the combined new and current zones. This state module can also test for
    changes by setting "test" keyword argument to true. Finally, this state module
    can delete the new zones from the Unbound zones by setting "delete" keyword
    argument to true.

    name
        Name of Salt state
    new_entries
        Unbound zones to be added or removed
    cert
        Path to certificate location
    key
        Path to key location
    hostname
        Host device URL
    cacert : False
        Path to certificate authority location
    **kwargs
        test : False
            When True, returns results without making changes to the Unbound zones
        delete : False
            When True, deletes new zones from the currernt Unbound zones
    """
    # Checks for "test" and "delete" keyword arguments, default to False if not provided
    test = kwargs.get("test", __opts__.get("test", False))
    remove = kwargs.get("delete", __opts__.get("remove", False))

    ret = {
        "name": name,
        "changes": {},
        "result": True,
        "comment": ""
    }
    # Get current NAT entries
    current_zones = __salt__["tnsr.unbound_zones_request"]("GET",
                                                            cert,
                                                            key,
                                                            cacert=cacert)

    # Parse current JSON and new YAML data
    current_zones = json.loads(current_zones)
    new_zones = {'netgate-unbound:local-zones': {'zone': yaml.safe_load(new_zones)}}

    merged_zones = __salt__["tnsr.merge_zones"](current_zones,
                                                new_zones,
                                                remove)

    # If item to be removed does not exist
    if remove and merged_zones == current_zones:
        ret["comment"] = "Unbound zones to be removed do not exist"
        return ret

    # If item to be added already exists
    if not remove and merged_zones == current_zones:
        ret["comment"] = "Unbound zones to be added already exist"
        return ret

    # If test, return old and new zones
    if test:
        ret["changes"] = {
            "old": current_zones,
            "new": merged_zones
        }
        ret["comment"] = "Unbound zones would have been updated"
        ret["result"] = None
        return ret

    # Update DNS zones
    __salt__["tnsr.unbound_zones_request"]("PUT",
                                            cert,
                                            key,
                                            cacert=cacert,
                                            payload=json.dumps(merged_zones))

    # Return successful update
    ret["changes"] = {
            "old": current_zones,
            "new": merged_zones,
        }
    ret["comment"] = "Successfully updated Unbound zones"
    ret["result"] = True
    return ret
