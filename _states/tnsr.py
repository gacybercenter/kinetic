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
from collections import OrderedDict
from time import sleep

__virtualname__ = 'tnsr'

def __virtual__():
    return __virtualname__

def nat_updated(name,
                new_entries,
                cert,
                key,
                hostname,
                cacert=False,
                **kwargs):
    """
    Update NAT entries on the TNSR platform.

    :param name: The name of the state.
    :param new_entries: The new NAT entries in YAML format, below is the raw json format from https://docs.netgate.com/tnsr/en/22.02/api.

    {
        "netgate-nat:mapping-table": {
            "mapping-entry": [
                {
                    "route-table-name": "string",
                    "external-if-name": "string",
                    "external-port": "string",
                    "local-port": "string",
                    "external-address": "string",
                    "transport-protocol": "icmp",
                    "out-to-in-only": true,
                    "twice-nat": true,
                    "local-address": "string"
                }
            ]
        }
    }

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


    Example sls state notation:
    tnsr_nat:
      tnsr.nat_updated:
        - name: tnsr_nat_updates
        - new_entries:
          - transport-protocol: "any"
            local-address: "<internal ip for nat termination>"
            local-port: "any"
            external-address: "<public ip>"
            external-port: "any"
            route-table-name: "<route table name>"
          - cert: <path to cert>
          - key: <path to key>
          - hostname: <tnsr API endpoint>
          - cacert: False
        

    """
    # Checks for "test" and "delete" keyword arguments, default to False if not provided
    test = kwargs.get("test", __opts__.get("test", False))

    ret = {
        "name": name,
        "changes": {},
        "result": False,
        "comment": ""
    }

    # Get current NAT entries
    current_entries = __salt__["tnsr.nat_entries_request"]("GET",
                                                            cert,
                                                            key,
                                                            hostname,
                                                            cacert=cacert)

    # Parse current JSON and new YAML data
    current_entries = json.loads(current_entries)
    new_entries = json.dumps(new_entries)
    new_entries = json.loads(new_entries)
    new_entries = {'netgate-nat:mapping-table': {'mapping-entry': new_entries }}

    merged_entries = __salt__["tnsr.merge_entries"](current_entries,
                                                    new_entries)

    # If test, return old and new entries
    if test:
        ret["changes"] = {
            "old": current_entries,
            "new": merged_entries,
        }
        ret["comment"] = "NAT entries would have been updated"
        ret["result"] = None
        return ret

    # If item to be removed does not exist
    if merged_entries == current_entries:
        ret["result"] = True
        ret["comment"] = "NAT entries already updated"
        return ret

    # Update NAT mapping entries
    response = __salt__["tnsr.nat_entries_request"]("PUT",
                                        cert,
                                        key,
                                        hostname,
                                        cacert=cacert,
                                        payload=json.dumps(merged_entries))

    sleep(10)
    current_entries = __salt__["tnsr.nat_entries_request"]("GET",
                                                            cert,
                                                            key,
                                                            hostname,
                                                            cacert=cacert)
    current_entries = json.loads(current_entries)

    if merged_entries == current_entries:
        # Return successful update
        ret["changes"] = {
                "old": current_entries,
                "new": merged_entries,
            }
        ret["comment"] = "Successfully updated NAT entries"
        ret["result"] = True
        return ret

    ret["comment"] = "Unable to apply NAT entries"
    return ret

def unbound_updated(name,
                    type,
                    new_zones,
                    cert,
                    key,
                    hostname,
                    cacert=False,
                    **kwargs):
    """
    Update the Unbound zones.

    :param name: The name of the state.
    :new_zones: The new Unbound zones in YAML format, below is the raw json format from https://docs.netgate.com/tnsr/en/22.02/api.

    local zone:
    {
        "zone": [
            {
            "description": "string",
            "type": "deny",
            "hosts": {
                "host": [
                    {
                        "ip-address": "string",
                        "host-name": "string"
                    },
                    {
                        "ip-address": "string",
                        "host-name": "string"
                    }
                ]
            },
            "zone-name": "string"
            }
        ]
    }

    forward zone:
    {
        "zone": [
            {
            "zone-name": "<zone name>",
            "forward-addresses": {
                "address": [
                        {
                            "ip-address": "<ip address>"
                        }
                ]
            }
        ]
    }

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

    Example sls state notation:
    tnsr_local_zone:
      tnsr.unbound_updated:
        - name: tnsr_unbound_updates
        - type: "local-zone|forward-zone"
        - new_zones:
          - zone-name: "<zone name>"
            type: "transparent"
            hosts:
              host:
                - ip-address: "<ip address>"
                  host-name: "<host name>"
          - zone-name: "<zone name>"
            type: "transparent"
            hosts:
              host:
                - ip-address: "<ip address>"
                  host-name: "<host name>"
                - ip-address: "<ip address>"
                  host-name: "<host name>"
        - cert: <path to cert>
        - key: <path to key>
        - hostname: <tnsr API endpoint>
        - cacert: False

    tnsr_forward_zone:
      tnsr.unbound_updated:
        - name: tnsr_unbound_updates
        - type: "local-zone|forward-zone"
        - new_zones:
          - zone-name: "<zone name>"
            forward-addresses:
              address:
                - ip-address: "<ip address>"
                - ip-address: "<ip address>"
        - cert: <path to cert>
        - key: <path to key>
        - hostname: <tnsr API endpoint>
        - cacert: False
    """

    # Checks for "test" and "delete" keyword arguments, default to False if not provided
    test = kwargs.get("test", __opts__.get("test", False))

    ret = {
        "name": name,
        "changes": {},
        "result": False,
        "comment": ""
    }


    # Get current NAT entries
    current_zones_request = __salt__["tnsr.unbound_zones_request"]("GET",
                                                            type,
                                                            cert,
                                                            key,
                                                            hostname,
                                                            cacert=cacert)


    # Parse current JSON and new YAML data
    current_zones = json.loads(current_zones_request)
    compare_zones = json.loads(current_zones_request)
    new_zones = json.dumps(new_zones)
    new_zones = json.loads(new_zones)
    if type == "local-zone":
        new_zones = {'netgate-unbound:local-zones': {'zone': new_zones}}
    elif type == "forward-zone":
        new_zones = {'netgate-unbound:forward-zones': {'zone': new_zones}}

    merged_zones = __salt__["tnsr.merge_zones"](type,
                                                current_zones,
                                                new_zones)

    # If test, return old and new zones
    if test:
        ret["changes"] = {
            "old": compare_zones,
            "new": merged_zones
        }
        ret["comment"] = "Unbound zones would have been updated"
        ret["result"] = None
        return ret

    print(f'current_zones: {compare_zones}')
    print(f'merged_zones: {merged_zones}')

    # If item to be added already exists
    if json.dumps(merged_zones) == json.dumps(compare_zones):
        ret["result"] = True
        ret["comment"] = "Unbound zones already updated"
        return ret

    # Update DNS zones
    __salt__["tnsr.unbound_zones_request"]("PUT",
                                            type,
                                            cert,
                                            key,
                                            hostname,
                                            cacert=cacert,
                                            payload=json.dumps(merged_zones))

    sleep(10)
    current_zones_request = __salt__["tnsr.unbound_zones_request"]("GET",
                                                            type,
                                                            cert,
                                                            key,
                                                            hostname,
                                                            cacert=cacert)
    current_zones = json.loads(current_zones_request)

    if json.dumps(merged_zones) == json.dumps(current_zones):
        # Return successful update
        ret["changes"] = {
                "old": current_zones,
                "new": merged_zones,
            }
        ret["comment"] = "Successfully updated Unbound zones"
        ret["result"] = True
        return ret

    ret["comment"] = "Applied Zone entries dont match expected entries"
    return ret
