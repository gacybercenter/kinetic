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

### NAT SECTION ###

def __virtual__():
    return __virtualname__

def get_nat_config():
    url = "http://hostname/restconf/data/netgate-nat:nat-config"
    response = requests.request("GET", url)
    return response.text

def update_nat_config():
    # Can be used to make or update the configuration
    url = "http://hostname/restconf/data/netgate-nat:nat-config"
    response = requests.request("PUT", url)
    return response.text

def delete_nat_config():
    url = "http://hostname/restconf/data/netgate-nat:nat-config"
    response = requests.request("DELETE", url)
    return response.text


def get_nat_config_static():
    url = "http://hostname/restconf/data/netgate-nat:nat-config/static"
    response = requests.request("GET", url)
    return response.text

def update_nat_config_static():
    # Can be used to make or update the configuration
    url = "http://hostname/restconf/data/netgate-nat:nat-config/static"
    response = requests.request("PUT", url)
    return response.text

def delete_nat_config_static():
    url = "http://hostname/restconf/data/netgate-nat:nat-config/static"
    response = requests.request("DELETE", url)
    return response.text


def get_nat_config_mapping_table():
    url = "http://hostname/restconf/data/netgate-nat:nat-config/static/mapping-table"
    response = requests.request("GET", url)
    return response.text

def update_nat_config_mapping_table():
    # Can be used to make or update the configuration
    url = "http://hostname/restconf/data/netgate-nat:nat-config/static/mapping-table"
    response = requests.request("PUT", url)
    return response.text

def delete_nat_config_mapping_table():
    url = "http://hostname/restconf/data/netgate-nat:nat-config/static/mapping-table"
    response = requests.request("DELETE", url)
    return response.text

#If the curley braces dont work, use the ASKII encoding : '%7B' for '{' and '%7D' for '}'

def make_nat_config_mapping_entry():
    url = "http://hostname/restconf/data/netgate-nat:nat-config/static/mapping-table/mapping-entry"
    response = requests.request("POST", url)
    return response.text

def get_nat_config_mapping_entry(protocol, local_addr, local_port, extr_addr, extr_port, table_name):
    url = "http://hostname/restconf/data/netgate-nat:nat-config/static/mapping-table/mapping-entry={"+protocol+"},{"+local_addr+"},{"+local_port+"},{"+extr_addr+"},{"+extr_port+"},{"+table_name+"}"
    response = requests.request("GET", url)
    return response.text

def update_nat_config_mapping_entry(protocol, local_addr, local_port, extr_addr, extr_port, table_name):
    url = "http://hostname/restconf/data/netgate-nat:nat-config/static/mapping-table/mapping-entry={"+protocol+"},{"+local_addr+"},{"+local_port+"},{"+extr_addr+"},{"+extr_port+"},{"+table_name+"}"
    response = requests.request("PUT", url)
    return response.text

def delete_nat_config_mapping_entry(protocol, local_addr, local_port, extr_addr, extr_port, table_name):
    url = "http://hostname/restconf/data/netgate-nat:nat-config/static/mapping-table/mapping-entry={"+protocol+"},{"+local_addr+"},{"+local_port+"},{"+extr_addr+"},{"+extr_port+"},{"+table_name+"}"
    response = requests.request("DELETE", url)
    return response.text


def get_nat_state():
    url = "http://hostname/restconf/data/netgate-nat:nat-state"
    response = requests.request("GET", url)
    return response.text


def get_nat_state_static():
    url = "http://hostname/restconf/data/netgate-nat:nat-state/static"
    response = requests.request("GET", url)
    return response.text


def get_nat_state_mapping_table():
    url = "http://hostname/restconf/data/netgate-nat:nat-state/static/mapping-table"
    response = requests.request("GET", url)
    return response.text


def get_nat_state_mapping_entry(protocol, local_addr, local_port, extr_addr, extr_port, table_name):
    url = "http://hostname/restconf/data/netgate-nat:nat-config/static/mapping-table/mapping-entry={"+protocol+"},{"+local_addr+"},{"+local_port+"},{"+extr_addr+"},{"+extr_port+"},{"+table_name+"}"
    response = requests.request("GET", url)
    return response.text


def get_nat_state_users():
    url = "http://hostname/restconf/data/netgate-nat:nat-state/users"
    response = requests.request("GET", url)
    return response.text


def get_nat_state_user(table, ip_addr):
    url = "http://hostname/restconf/data/netgate-nat:nat-state/users/user={"+table+"},{"+ip_addr+"}"
    response = requests.request("GET", url)
    return response.text


def get_nat_state_session(table, ip_addr, session_id):
    url = "http://hostname/restconf/data/netgate-nat:nat-state/users/user={"+table+"},{"+ip_addr+"}/session={"+session_id+"}"
    response = requests.request("GET", url)
    return response.text

### UNBOUND SECTION ###

def get_unbound_config():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config():
    # Can be used to make or update the configuration
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config"
    response = requests.request("DELETE", url)
    return response.text


def get_unbound_config_daemon():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_daemon():
    # Can be used to make or update the configuration
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_daemon():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon"
    response = requests.request("DELETE", url)
    return response.text


def get_unbound_config_forward_zones():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_forward_zones():
    # Can be used to make or update the configuration
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_forward_zones():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones"
    response = requests.request("DELETE", url)
    return response.text

#If the curley braces dont work, use the ASKII encoding : '%7B' for '{' and '%7D' for '}'

def make_unbound_config_forward_zone():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones/zone"
    response = requests.request("POST", url)
    return response.text

def get_unbound_config_forward_zone(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones/zone={"+zone_name+"}"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_forward_zone(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones/zone={"+zone_name+"}"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_forward_zone(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones/zone={"+zone_name+"}"
    response = requests.request("DELETE", url)
    return response.text


def get_unbound_config_forward_address(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones/zone={"+zone_name+"}/forward-address"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_forward_address(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones/zone={"+zone_name+"}/forward-address"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_forward_address(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones/zone={"+zone_name+"}/forward-address"
    response = requests.request("DELETE", url)
    return response.text


def make_unbound_config_address(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones/zone={"+zone_name+"}/forward-address/address"
    response = requests.request("POST", url)
    return response.text

def get_unbound_config_address(zone_name, ip_addr):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones/zone={"+zone_name+"}/forward-address/address={"+ip_addr+"}"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_address(zone_name, ip_addr):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones/zone={"+zone_name+"}/forward-address/address={"+ip_addr+"}"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_address(zone_name, ip_addr):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones/zone={"+zone_name+"}/forward-address/address={"+ip_addr+"}"
    response = requests.request("DELETE", url)
    return response.text


def get_unbound_config_forward_hosts(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones/zone={"+zone_name+"}/forward-hosts"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_forward_hosts(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones/zone={"+zone_name+"}/forward-hosts"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_forward_hosts(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/forward-zones/zone={"+zone_name+"}/forward-hosts"
    response = requests.request("DELETE", url)
    return response.text


def get_unbound_config_server():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_server():
    # Can be used to make or update the configuration
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_server():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server"
    response = requests.request("DELETE", url)
    return response.text


def get_unbound_config_access_controls():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/access-control"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_access_controls():
    # Can be used to make or update the configuration
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/access-control"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_access_controls():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/access-control"
    response = requests.request("DELETE", url)
    return response.text


def make_unbound_config_access_control():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/access-control/access"
    response = requests.request("POST", url)
    return response.text

def get_unbound_config_access_control(ip_prefix):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/access-control/access={"+ip_prefix+"}"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_access_control(ip_prefix):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/access-control/access={"+ip_prefix+"}"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_access_control(ip_prefix):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/access-control/access={"+ip_prefix+"}"
    response = requests.request("DELETE", url)
    return response.text


def get_unbound_config_interfaces():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/interfaces"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_interfaces():
    # Can be used to make or update configuration
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/interfaces"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_interfaces():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/interfaces"
    response = requests.request("DELETE", url)
    return response.text


def make_unbound_config_interface():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/interfaces/interface"
    response = requests.request("POST", url)
    return response.text

def get_unbound_config_interface(ip_addr):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/interfaces/interface={"+ip_addr+"}"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_interface(ip_addr):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/interfaces/interface={"+ip_addr+"}"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_interface(ip_addr):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/interfaces/interface={"+ip_addr+"}"
    response = requests.request("DELETE", url)
    return response.text


def get_unbound_config_zones():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_zones():
    # Can be used to make or update configuration
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_zones():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones"
    response = requests.request("DELETE", url)
    return response.text


def make_unbound_config_zone():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones/zone"
    response = requests.request("POST", url)
    return response.text

def get_unbound_config_zone(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones/zone={"+zone_name+"}"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_zone(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones/zone={"+zone_name+"}"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_zone(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones/zone={"+zone_name+"}"
    response = requests.request("DELETE", url)
    return response.text


def get_unbound_config_hosts(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones/zone={"+zone_name+"}/hosts"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_hosts(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones/zone={"+zone_name+"}/hosts"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_hosts(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones/zone={"+zone_name+"}/hosts"
    response = requests.request("DELETE", url)
    return response.text


def make_unbound_config_host(zone_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones/zone={"+zone_name+"}/hosts/host"
    response = requests.request("POST", url)
    return response.text

def get_unbound_config_host(zone_name, host_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones/zone={"+zone_name+"}/hosts/host={"+host_name+"}"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_host(zone_name, host_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones/zone={"+zone_name+"}/hosts/host={"+host_name+"}"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_host(zone_name, host_name):
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones/zone={"+zone_name+"}/hosts/host={"+host_name+"}"
    response = requests.request("DELETE", url)
    return response.text


def get_unbound_config_outgoing_interfaces():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/outgoing-interfaces"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_outgoing_interfaces():
    # Can be used to make or update configuration
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/outgoing-interfaces"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_outgoing_interfaces():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/daemon/server/outgoing-interfaces"
    response = requests.request("DELETE", url)
    return response.text


def get_unbound_config_parameters():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/parameters"
    response = requests.request("GET", url)
    return response.text

def update_unbound_config_parameters():
    # Can be used to make or update configuration
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/parameters"
    response = requests.request("PUT", url)
    return response.text

def delete_unbound_config_parameters():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config/parameters"
    response = requests.request("DELETE", url)
    return response.text


def make_unbound_config_operation():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-config-operation"
    response = requests.request("POST", url)
    return response.text

def make_unbound_control():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-control"
    response = requests.request("POST", url)
    return response.text

def make_unbound_coredump():
    url = "http://hostname/restconf/data/netgate-unbound:unbound-coredump"
    response = requests.request("POST", url)
    return response.text


### COMMIT SECTION ###


def netconfig_commit():
    url = "http://hostname/restconf/operations/ietf-netconf:commit"
    response = requests.request("POST", url)
    return response.text

def netconfig_cancel_commit():
    url = "http://hostname/restconf/operations/ietf-netconf:cancel-commit"
    response = requests.request("POST", url)
    return response.text

def netconfig_close_session():
    url = "http://hostname/restconf/operations/ietf-netconf:close-session"
    response = requests.request("POST", url)
    return response.text

def netconfig_delete_config():
    url = "http://hostname/restconf/operations/ietf-netconf:delete-config"
    response = requests.request("POST", url)
    return response.text

def netconfig_discard_changes():
    url = "http://hostname/restconf/operations/ietf-netconf:discard-changes"
    response = requests.request("POST", url)
    return response.text

def netconfig_edit_config():
    url = "http://hostname/restconf/operations/ietf-netconf:edit-config"
    response = requests.request("POST", url)
    return response.text

def netconfig_get():
    url = "http://hostname/restconf/operations/ietf-netconf:get"
    response = requests.request("POST", url)
    return response.text

def netconfig_get_config():
    url = "http://hostname/restconf/operations/ietf-netconf:get-config"
    response = requests.request("POST", url)
    return response.text

def netconfig_kill_session():
    url = "http://hostname/restconf/operations/ietf-netconf:kill-session"
    response = requests.request("POST", url)
    return response.text

def netconfig_lock():
    url = "http://hostname/restconf/operations/ietf-netconf:lock"
    response = requests.request("POST", url)
    return response.text


def netconfig_unlock():
    url = "http://hostname/restconf/operations/ietf-netconf:unlock"
    response = requests.request("POST", url)
    return response.text

def netconfig_validate():
    url = "http://hostname/restconf/operations/ietf-netconf:validate"
    response = requests.request("POST", url)
    return response.text
