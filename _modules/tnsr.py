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
    def __init__(self, hostname: str, cert: str, key: str, cacert: str, headers: dict):
        self.hostname = hostname
        self.cert = cert
        self.key = key
        self.cacert = cacert
        self.headers = headers

    ### Debugging ###

    def get_headers(self):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config"
        response = requests.request("OPTIONS",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers)
        return response.text

    ### NAT SECTION ###

    def get_nat_config(self):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config"
        response = requests.request("GET",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers)
        return response.text

    def update_nat_config(self, 
                        payload):
        # Can be used to make or update the configuration
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config"
        response = requests.request("PUT",
                                    url,
                                    json=payload,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text

    def delete_nat_config(self):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config"
        response = requests.request("DELETE",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text


    #If the curley braces dont work, use the ASKII encoding : '%7B' for '{' and '%7D' for '}'

    def update_nat_static(self, 
                            payload):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config/static"
        response = requests.request("PUT",
                                    url,
                                    data=payload,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text

    def get_nat_mapping_tables(self):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table"
        response = requests.request("GET",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text


    def update_nat_mapping_tables(self, 
                                payload):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table"
        response = requests.request("PUT",
                                    url,
                                    data=payload,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text

    def make_nat_mapping_tables(self, 
                            payload):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table"
        response = requests.request("POST",
                                    url,
                                    data=payload,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text

    def update_nat_mapping_tables(self, 
                            payload):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table"
        response = requests.request("PUT",
                                    url,
                                    data=payload,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text

    def get_nat_entry(self, **kwargs):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table/mapping-entry=%7B{transport_protocol}%7D,%7B{local_address}%7D,%7B{local_port}%7D,%7B{external_address}%7D,%7B{external_port}%7D,%7B{route_table_name}%7D"
        response = requests.request("GET",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text

    def delete_nat_entry(self, **kwargs):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table/mapping-entry=%7B{transport_protocol}%7D,%7B{local_address}%7D,%7B{local_port}%7D,%7B{external_address}%7D,%7B{external_port}%7D,%7B{route_table_name}%7D"
        response = requests.request("DELETE",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text


    def get_nat_state(self):
        url = f"{self.hostname}/restconf/data/netgate-nat:nat-state"
        response = requests.request("GET",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text

    ### UNBOUND SECTION ###

    def get_unbound_config(self):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config"
        response = requests.request("GET",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text


    def update_unbound_config(self, 
                            payload):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config"
        response = requests.request("PUT",
                                    url,
                                    data=payload,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text



    def delete_unbound_config(self):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config"
        response = requests.request("DELETE",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text


    def get_unbound_zones(self):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones"
        response = requests.request("GET",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text


    def update_unbound_zones(self,
                            payload):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones"
        response = requests.request("PUT",
                                    url,
                                    data=payload,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text


    def get_unbound_zone_name(self, 
                                zone_name):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones/zone={zone_name}"
        url = url.format(zone_name=zone_name)
        response = requests.request("GET",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text

    def make_unbound_zone_name(self, 
                                zone_name,
                                payload):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config/netgate-unbound:daemon/netgate-unbound:server/netgate-unbound:local-zones/netgate-unbound:zone={zone_name}"
        url = url.format(zone_name=zone_name)
        response = requests.request("POST",
                                    url,
                                    data=payload,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text

    def update_unbound_zone_name(self, 
                                zone_name,
                                payload):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones/zone={zone_name}"
        url = url.format(zone_name=zone_name)
        response = requests.request("PUT",
                                    url,
                                    data=payload,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text

    def delete_unbound_zone_name(self, 
                                zone_name):
        url = f"{self.hostname}/restconf/data/netgate-unbound:unbound-config/static/mapping-table/local-zones/zone={zone_name}"
        url = url.format(zone_name=zone_name)
        response = requests.request("DELETE",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text

    ### COMMIT SECTION ###

    def netconfig_commit(self):
        url = f"{self.hostname}/restconf/operations/ietf-netconf:commit"
        response = requests.request("POST",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text


    def netconfig_cancel_commit(self):
        url = f"{self.hostname}/restconf/operations/ietf-netconf:cancel-commit"
        url = f"{self.hostname}/restconf/operations/ietf-netconf:commit"
        response = requests.request("POST",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text


    def netconfig_close_session(self,
                                session_id):
        url = f"{self.hostname}/restconf/operations/ietf-netconf:close-session"
        data = {"session-id": session_id}
        response = requests.request("POST",
                                    url,
                                    json=data,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text


    def netconfig_delete_config(self,
                                target):
        url = f"{self.hostname}/restconf/operations/ietf-netconf:delete-config"
        data = {"target": target}
        response = requests.request("POST",
                                    url,
                                    json=data,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text


    def netconfig_discard_changes(self):
        url = f"{self.hostname}/restconf/operations/ietf-netconf:discard-changes"
        response = requests.request("POST",
                                    url,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text


    def netconfig_edit_config(self, 
                            payload, 
                            config_type, 
                            target):
        url = f"{self.hostname}/restconf/operations/ietf-netconf:edit-config"
        data = {
            "ietf-netconf:edit-config": {
                "target": target,
                "config-type": config_type,
                "config": payload
            }
        }
        response = requests.request("POST",
                                    url,
                                    json=data,
                                    cert=(self.cert, self.key),
                                    verify=self.cacert,
                                    headers=self.headers,)
        return response.text

