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

__virtualname__ = 'tnsr'

def __virtual__():
    return __virtualname__
class Session:
    def __init__(self, hostname: str, cert: str, key: str, cacert: str):
        self.hostname = hostname
        self.cert = cert
        self.key = key
        self.cacert = cacert

    ### NAT SECTION ###

    def get_nat_config(self):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config"
        headers = {'Content-Type': 'application/json'}
        try:
            response = requests.get(url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to get nat config. {err}")

    def update_nat_config(self, 
                        payload):
        # Can be used to make or update the configuration
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config"
        headers = {'Content-Type': 'application/json'}
        try:
            response = requests.put(url,
                                cert=(self.cert, self.key),
                                verify=self.cacert, 
                                data=json.dumps(payload), 
                                headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to retrieve nat config. {err}")

    def delete_nat_config(self):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config"
        headers = {'Content-Type': 'application/json'}
        try:
            response = requests.delete(url, 
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to delete nat config. {err}")


    #If the curley braces dont work, use the ASKII encoding : '%7B' for '{' and '%7D' for '}'

    def update_nat_config_mapping_entry(self,
                                        protocol, 
                                        local_addr, 
                                        local_port, 
                                        extr_addr, 
                                        extr_port, 
                                        table_name):
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
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table"
        try:
            response = requests.post(url, 
                                cert=(self.cert, self.key),
                                verify=self.cacert,
                                data=json.dumps(data), 
                                headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to update nat config mapping entry. {err}")


    def get_nat_config_mapping_entry(self,
                                    protocol, 
                                    local_addr, 
                                    local_port, 
                                    extr_addr, 
                                    extr_port, 
                                    table_name):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table/mapping-entry?protocol={protocol}&local-addr={local_addr}&local-port={local_port}&extr-addr={extr_addr}&extr-port={extr_port}&table-name={table_name}"
        url = url.format(protocol=protocol,
                        local_addr=local_addr, 
                        local_port=local_port, 
                        extr_addr=extr_addr, 
                        extr_port=extr_port, 
                        table_name=table_name)
        try:
            response = requests.get(url, 
                                cert=(self.cert, self.key),
                                verify=self.cacert,)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to get nat config mapping entry. {err}")


    def delete_nat_config_mapping_entry(self,
                                        protocol, 
                                        local_addr, 
                                        local_port, 
                                        extr_addr, 
                                        extr_port, 
                                        table_name):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table/mapping-entry?protocol={protocol}&local-addr={local_addr}&local-port={local_port}&extr-addr={extr_addr}&extr-port={extr_port}&table-name={table_name}"
        url = url.format(protocol=protocol, 
                        local_addr=local_addr, 
                        local_port=local_port, 
                        extr_addr=extr_addr, 
                        extr_port=extr_port, 
                        table_name=table_name)
        try:
            response = requests.delete(url, 
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to delete nat config mapping entry. {err}")



    def get_nat_state(self):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-state"
        headers = {'Content-Type': 'application/json'}
        try:
            response = requests.get(url, 
                                cert=(self.cert, self.key),
                                verify=self.cacert,
                                headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to get nat state. {err}")


    def get_nat_state_mapping_entry(self,
                                    protocol, 
                                    local_addr, 
                                    local_port, 
                                    extr_addr, 
                                    extr_port, 
                                    table_name):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table/mapping-entry?protocol={protocol}&local-addr={local_addr}&local-port={local_port}&extr-addr={extr_addr}&extr-port={extr_port}&table-name={table_name}"
        url = url.format(protocol=protocol, 
                        local_addr=local_addr, 
                        local_port=local_port, 
                        extr_addr=extr_addr, 
                        extr_port=extr_port, 
                        table_name=table_name)
        headers = {'Content-Type': 'application/json'}
        try:
            response = requests.get(url, 
                                cert=(self.cert, self.key),
                                verify=self.cacert,
                                headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to get nat state mapping entry. {err}")


    ### UNBOUND SECTION ###

    def get_unbound_config(self):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config"
        headers = {'Content-Type': 'application/json'}
        try:
            response = requests.get(url, 
                                cert=(self.cert, self.key),
                                verify=self.cacert,
                                headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to get unbound config. {err}")


    def update_unbound_config(self, 
                            payload):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config"
        headers = {'Content-Type': 'application/json'}
        try:
            response = requests.put(url, 
                                cert=(self.cert, self.key),
                                verify=self.cacert,
                                json=payload, 
                                headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to update unbound config. {err}")


    def delete_unbound_config(self):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config"
        headers = {'Content-Type': 'application/json'}
        try:
            response = requests.delete(url, 
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to delete unbound config. {err}")


    def get_unbound_config_host(self, 
                                zone_name, 
                                zone_type):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones?zone-name={zone_name}&type={zone_type}"
        url = url.format(zone_name=zone_name, 
                        zone_type=zone_type)
        headers = {'Content-Type': 'application/json'}
        try:
            response = requests.get(url, 
                                cert=(self.cert, self.key),
                                verify=self.cacert,
                                headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to get unbound config host. {err}")


    def update_unbound_config_host(self,
                                    zone_name, 
                                    zone_type, 
                                    host_name_1, 
                                    ip_address_1, 
                                    host_name_2, 
                                    ip_address_2):
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
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table"
        try:
            response = requests.post(url, 
                                cert=(self.cert, self.key),
                                verify=self.cacert,
                                data=json.dumps(data), 
                                headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to update unbound config host. {err}")



    def delete_unbound_config_host(self,
                                    zone_name, 
                                    zone_type, 
                                    host_name_1, 
                                    ip_address_1, 
                                    host_name_2, 
                                    ip_address_2):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones"
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
        try:
            response = requests.delete(url, 
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    json=payload, 
                                    headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to delete unbound config host. {err}")


    ### COMMIT SECTION ###

    def netconfig_commit(self):
        url = f"{self.hostname}/restconf/operations/ietf-netconf:commit"
        headers = {'Content-Type': 'application/json'}
        try:
            response = requests.post(url, 
                                cert=(self.cert, self.key),
                                verify=self.cacert,
                                headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to commit netconfig. {err}")


    def netconfig_cancel_commit(self):
        url = f"{self.hostname}/restconf/operations/ietf-netconf:cancel-commit"
        headers = {'Content-Type': 'application/json'}
        try:
            response = requests.post(url, 
                                cert=(self.cert, self.key),
                                verify=self.cacert,
                                headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to cancel commit netconfig. {err}")


    def netconfig_close_session(self,
                                session_id):
        url = f"{self.hostname}/restconf/operations/ietf-netconf:close-session"
        headers = {'Content-Type': 'application/json'}
        data = {"session-id": session_id}
        try:
            response = requests.post(url, 
                                cert=(self.cert, self.key),
                                verify=self.cacert,
                                json=data,
                                headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to close session netconfig. {err}")


    def netconfig_delete_config(self,
                                target):
        url = f"{self.hostname}/restconf/operations/ietf-netconf:delete-config"
        headers = {'Content-Type': 'application/json'}
        data = {"target": target}
        try:
            response = requests.post(url, 
                                cert=(self.cert, self.key),
                                verify=self.cacert,
                                json=data,
                                headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to delete netconfig. {err}")


    def netconfig_discard_changes(self):
        url = f"{self.hostname}/restconf/operations/ietf-netconf:discard-changes"
        headers = {'Content-Type': 'application/json'}
        try:
            response = requests.post(url,
                                cert=(self.cert, self.key),
                                verify=self.cacert,
                                headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to discard changes netconfig. {err}")


    def netconfig_edit_config(self, 
                            payload, 
                            config_type, 
                            target):
        url = f"{self.hostname}/restconf/operations/ietf-netconf:edit-config"
        headers = {'Content-Type': 'application/json'}
        data = {
            "ietf-netconf:edit-config": {
                "target": target,
                "config-type": config_type,
                "config": payload
            }
        }
        try:
            response = requests.post(url, 
                                cert=(self.cert, self.key),
                                verify=self.cacert,
                                json=data, 
                                headers=headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as err:
            raise ValueError(f"Failed to edit config netconfig. {err}")

