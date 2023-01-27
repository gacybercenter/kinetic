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
import json

hostname = 'http://tnsr.internal.gacyberrange.org'

# Remove before commiting (sensitive).
cert = "~/gcc/data-center/tnsr/rest_api/tnsr-gacyberrange.crt"
key = "~/gcc/data-center/tnsr/rest_api/tnsr-gacyberrange.key" 
cacert = "~/gcc/data-center/tnsr/rest_api/tnsr-rest_api.crt"

__virtualname__ = 'tnsr'

def __virtual__():
    return __virtualname__

### NAT SECTION ###

def get_nat_config(hostname, cert, key, cacert):
    url = f"{hostname}/restconf/data/netgate-nat:nat-config"
    headers = {'Content-Type': 'application/json'}
    response = requests.get(url,
                            cert=(cert, key),
                            verify=cacert,
                            headers=headers)
    if response.status_code != 200:
        raise ValueError("Failed to retrieve nat config with status code: " + str(response.status_code))
    return response.json()

def update_nat_config(data, 
                    hostname):
    # Can be used to make or update the configuration
    url = f"{hostname}/restconf/data/netgate-nat:nat-config"
    headers = {'Content-Type': 'application/json'}
    response = requests.put(url, 
                            data=json.dumps(data), 
                            headers=headers)
    if response.status_code != 200:
        raise ValueError("Failed to update nat config with status code: " + str(response.status_code))
    return response.json()

def delete_nat_config(hostname):
    url = f"{hostname}/restconf/data/netgate-nat:nat-config"
    headers = {'Content-Type': 'application/json'}
    response = requests.delete(url, 
                                headers=headers)
    if response.status_code != 200:
        raise ValueError("Failed to delete nat config with status code: " + str(response.status_code))
    return response.json()

#If the curley braces dont work, use the ASKII encoding : '%7B' for '{' and '%7D' for '}'

def update_nat_config_mapping_entry(protocol, 
                                    local_addr, 
                                    local_port, 
                                    extr_addr, 
                                    extr_port, 
                                    table_name,
                                    hostname):
    data = {
        "netgate-nat:nat-config": {
            "static": {
                "mapping-table": {
                    "mapping-entry": {
                        "protocol": protocol,
                        "local-addr": local_addr,
                        "local-port": local_port,
                        "extr-addr": extr_addr,
                        "extr-port": extr_port,
                        "table-name": table_name
                    }
                }
            }
        }
    }
    headers = {'Content-Type': 'application/json'}
    url = f"{hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table"
    response = requests.post(url, 
                            data=json.dumps(data), 
                            headers=headers)
    return response.text

def get_nat_config_mapping_entry(protocol, 
                                local_addr, 
                                local_port, 
                                extr_addr, 
                                extr_port, 
                                table_name,
                                hostname):
    url = f"{hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table/mapping-entry?protocol={protocol}&local-addr={local_addr}&local-port={local_port}&extr-addr={extr_addr}&extr-port={extr_port}&table-name={table_name}"
    url = url.format(protocol=protocol,
                    local_addr=local_addr, 
                    local_port=local_port, 
                    extr_addr=extr_addr, 
                    extr_port=extr_port, 
                    table_name=table_name)
    response = requests.get(url)
    return response.text

def delete_nat_config_mapping_entry(protocol, 
                                    local_addr, 
                                    local_port, 
                                    extr_addr, 
                                    extr_port, 
                                    table_name,
                                    hostname):
    url = f"{hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table/mapping-entry?protocol={protocol}&local-addr={local_addr}&local-port={local_port}&extr-addr={extr_addr}&extr-port={extr_port}&table-name={table_name}"
    url = url.format(protocol=protocol, 
                    local_addr=local_addr, 
                    local_port=local_port, 
                    extr_addr=extr_addr, 
                    extr_port=extr_port, 
                    table_name=table_name)
    response = requests.delete(url)
    return response.text


def get_nat_state(hostname):
    url = f"{hostname}/restconf/data/netgate-nat:nat-state"
    headers = {'Content-Type': 'application/json'}
    response = requests.get(url, 
                            headers=headers)
    if response.status_code != 200:
        raise ValueError("Failed to retrieve nat state with status code: " + str(response.status_code))
    return response.json()

def get_nat_state_mapping_entry(protocol, 
                                local_addr, 
                                local_port, 
                                extr_addr, 
                                extr_port, 
                                table_name,
                                hostname):
    url = f"{hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table/mapping-entry?protocol={protocol}&local-addr={local_addr}&local-port={local_port}&extr-addr={extr_addr}&extr-port={extr_port}&table-name={table_name}"
    url = url.format(protocol=protocol, 
                    local_addr=local_addr, 
                    local_port=local_port, 
                    extr_addr=extr_addr, 
                    extr_port=extr_port, 
                    table_name=table_name)
    headers = {'Content-Type': 'application/json'}
    response = requests.get(url, 
                            headers=headers)
    if response.status_code != 200:
        raise ValueError("Failed to retrieve nat state mapping entry with status code: " + str(response.status_code))
    return response.json()

### UNBOUND SECTION ###

def get_unbound_config(hostname):
    url = f"{hostname}/restconf/data/netgate-unbound:unbound-config"
    headers = {'Content-Type': 'application/json'}
    response = requests.get(url, 
                            headers=headers)
    if response.status_code != 200:
        raise ValueError("Failed to retrieve unbound config with status code: " + str(response.status_code))
    return response.json()

def update_unbound_config(payload, 
                        hostname):
    url = f"{hostname}/restconf/data/netgate-unbound:unbound-config"
    headers = {'Content-Type': 'application/json'}
    response = requests.put(url, 
                            json=payload, 
                            headers=headers)
    if response.status_code != 200:
        raise ValueError("Failed to update unbound config with status code: " + str(response.status_code))
    return response.json()

def delete_unbound_config(hostname):
    url = f"{hostname}/restconf/data/netgate-unbound:unbound-config"
    headers = {'Content-Type': 'application/json'}
    response = requests.delete(url, 
                                headers=headers)
    if response.status_code != 200:
        raise ValueError("Failed to delete unbound config with status code: " + str(response.status_code))


def get_unbound_config_host(zone_name, 
                            zone_type,
                            hostname):
    url = f"{hostname}/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones?zone-name={zone_name}&type={zone_type}"
    url = url.format(zone_name=zone_name, 
                    zone_type=zone_type)
    headers = {'Content-Type': 'application/json'}
    response = requests.get(url, 
                            headers=headers)
    return response.text

def update_unbound_config_host(zone_name, 
                                zone_type, 
                                host_name_1, 
                                ip_address_1, 
                                host_name_2, 
                                ip_address_2,
                                hostname):
    data={
        "netgate-unbound:unbound-config": {
            "daemon": {
                "server": {
                    "local-zones": {
                        "zone": {
                            "zone-name": zone_name,
                            "type": zone_type,
                            "hosts": {
                                "host": [
                                    {
                                        "host-name": host_name_1,
                                        "ip-address": [
                                            ip_address_1
                                        ]
                                    },
                                    {
                                        "host-name": host_name_2,
                                        "ip-address": [
                                            ip_address_2
                                        ]
                                    }
                                ]
                            }
                        }
                    }
                }
            }
        }
    }
    headers = {'Content-Type': 'application/json'}
    url = f"{hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table"
    response = requests.post(url, 
                            data=json.dumps(data), 
                            headers=headers)
    return response.text


def delete_unbound_config_host(zone_name, 
                                zone_type, 
                                host_name_1, 
                                ip_address_1, 
                                host_name_2, 
                                ip_address_2,
                                hostname):
    url = f"{hostname}/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones"
    payload = {
        "zone": {
            "zone-name": zone_name,
            "type": zone_type,
            "hosts": {
                "host": [
                    {
                        "host-name": host_name_1,
                        "ip-address": [
                            ip_address_1
                        ]
                    },
                    {
                        "host-name": host_name_2,
                        "ip-address": [
                            ip_address_2
                        ]
                    }
                ]
            }
        }
    }
    headers = {'Content-Type': 'application/json'}
    response = requests.delete(url, 
                                json=payload, 
                                headers=headers)
    return response.text

### COMMIT SECTION ###

def netconfig_commit(hostname):
    url = f"{hostname}/restconf/operations/ietf-netconf:commit"
    headers = {'Content-Type': 'application/json'}
    response = requests.post(url, 
                            headers=headers)
    if response.status_code != 200:
        raise ValueError("Failed to commit with status code: " + str(response.status_code))
    return response.text

def netconfig_cancel_commit(hostname):
    url = f"{hostname}/restconf/operations/ietf-netconf:cancel-commit"
    headers = {'Content-Type': 'application/json'}
    response = requests.post(url, 
                            headers=headers)
    if response.status_code != 200:
        raise ValueError("Failed to cancel commit with status code: " + str(response.status_code))
    return response.text

def netconfig_close_session(session_id,
                            hostname):
    url = f"{hostname}/restconf/operations/ietf-netconf:close-session"
    headers = {'Content-Type': 'application/json'}
    data = {"session-id": session_id}
    response = requests.post(url, 
                            headers=headers, 
                            json=data)
    if response.status_code != 200:
        raise ValueError("Failed to close session with status code: " + str(response.status_code))
    return response.text

def netconfig_delete_config(target,
                            hostname):
    url = f"{hostname}/restconf/operations/ietf-netconf:delete-config"
    headers = {'Content-Type': 'application/json'}
    data = {"target": target}
    response = requests.post(url, headers=headers, json=data)
    if response.status_code != 200:
        raise ValueError("Failed to delete config with status code: " + str(response.status_code))
    return response.text

def netconfig_discard_changes(hostname):
    url = f"{hostname}/restconf/operations/ietf-netconf:discard-changes"
    headers = {'Content-Type': 'application/json'}
    response = requests.post(url, headers=headers)
    if response.status_code != 200:
        raise ValueError("Failed to discard changes with status code: " + str(response.status_code))
    return response.text

def netconfig_edit_config(payload, 
                        config_type, 
                        target, 
                        hostname):
    url = f"{hostname}/restconf/operations/ietf-netconf:edit-config"
    headers = {'Content-Type': 'application/json'}
    data = {
        "ietf-netconf:edit-config": {
            "target": target,
            "config-type": config_type,
            "config": payload
        }
    }
    response = requests.post(url, 
                            json=data, 
                            headers=headers)
    return response.text
