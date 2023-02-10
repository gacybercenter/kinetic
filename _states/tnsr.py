"""
Copyright 2020 Augusta University

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Tnsr State Module
"""

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
    Update NAT entries on the TNSR platform.

    :param name: The name of the state.
    :param new_entries: The new NAT entries in YAML format.
    :param cert: The path to the client certificate file.
    :param key: The path to the client private key file.
    :param cacert: The path to the CA certificate file.
    :param kwargs: Additional keyword arguments.
        :test: Optional argument to test the update and return changes (default is False).
        :delete: Optional argument to delete the specified NAT entries (default is False).
    :return: A dictionary with the following keys:
        :name: The name of the state.
        :changes: A dictionary with the old and new NAT entries.
        :result: True if the update was successful, None if in test mode, and False otherwise.
        :comment: A string describing the result of the update.
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
    Update the Unbound zones.

    :param name: The name of the state.
    :new_zones: The new Unbound zones in YAML format.
    :cert: The path to the certificate file.
    :key: The path to the private key file.
    :cacert: The path to the CA certificate file.
    :kwargs: Optional keyword arguments:
        :test: Boolean value that controls whether the function will execute changes
            (False) or only return what changes would occur (True). The default
            value is False.
        :delete: Boolean value that controls whether the zones will be deleted (True)
            or added (False). The default value is False.
    :return: A dictionary with the following keys:
        :name: The name of the state.
        :changes: A dictionary with the old and new Unbound zones.
        :result: A boolean value indicating the success or failure of the update.
        :comment: A string with a summary of the operation and the result.
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
