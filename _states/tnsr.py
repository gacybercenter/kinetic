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

from _modules.tnsr import Session

__virtualname__ = 'tnsr'

def __virtual__():
    return __virtualname__

def managed(name):
    """
    Ensure that the NAT config is managed by Salt.
    """
    ret = {"name": name, "changes": {}, "result": True, "comment": ""}

    nat_config = Session(hostname, cert, key, cacert)
    # Check if the NAT config is already managed by Salt
    mapping_table = nat_config.get_nat_config_mapping_table()
    if mapping_table:
        ret["comment"] = "NAT config is already managed by Salt"
        return ret

    # Update NAT config mapping entry
    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = "NAT config mapping entry would be updated"
        return ret

    protocol = "tcp"
    local_addr = "192.168.1.100"
    local_port = "80"
    extr_addr = "10.0.0.1"
    extr_port = "8080"
    table_name = "my-table"

    result = nat_config.update_nat_config_mapping_entry(protocol, 
                                                        local_addr, 
                                                        local_port, 
                                                        extr_addr, 
                                                        extr_port, 
                                                        table_name)
    ret["changes"]["updated"] = result
    if not result:
        ret["result"] = False
        ret["comment"] = "Failed to update NAT config mapping entry"
    return ret


def dns_updated(name):
    """
    Ensure that the DNS config is managed by Salt.
    """
    ret = {"name": name, "changes": {}, "result": True, "comment": ""}

    dns_config = Session(hostname, cert, key, cacert)
    # Check if the NAT config is already managed by Salt
    hosts = dns_config.get_unbound_config_hosts()
    if hosts:
        ret["comment"] = "DNS config is already managed by Salt"
        return ret

    # Update NAT config mapping entry
    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = "DNS config mapping entry would be updated"
        return ret

    zone_name = "among us"
    zone_type = "imposter"
    host_name_1 = "Red"
    ip_address_1 = "10.0.0.1"
    host_name_2 = "Blue"
    ip_address_2 = "10.0.0.2"

    result = dns_config.update_unbound_config_host(zone_name, 
                                                    zone_type, 
                                                    host_name_1, 
                                                    ip_address_1, 
                                                    host_name_2, 
                                                    ip_address_2)
    ret["changes"]["updated"] = result
    if not result:
        ret["result"] = False
        ret["comment"] = "Failed to update DNS config mapping entry"
    return ret




### Templates ###

def dns_updated(name, primary_server, secondary_server):
    """
    Ensure that the DNS settings in TNSR are updated.
    """
    ret = {"name": name, "changes": {}, "result": True, "comment": ""}
    # Check if the DNS settings are already correct
    if __salt__["tnsr.check_dns"](primary_server, secondary_server):
        ret["comment"] = "DNS settings are already correct"
        return ret
    # Update the DNS settings
    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = "DNS settings would be updated"
        return ret
    result = __salt__["tnsr.update_dns"](primary_server, secondary_server)
    ret["changes"]["updated"] = result["name"]
    if not result["result"]:
        ret["result"] = False
        ret["comment"] = "Failed to update DNS settings"
    return ret

def managed(name, user, password, host, port=80, api_key=None, verify_ssl=True):
    """
    Ensure that the TNSR API is managed by Salt.
    """
    ret = {"name": name, "changes": {}, "result": True, "comment": ""}
    # Check if the TNSR API is already managed by Salt
    if "tnsr" in __salt__:
        ret["comment"] = "TNSR API is already managed by Salt"
        return ret
    # Add the TNSR API to the Salt execution module
    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = "TNSR API would be added to the Salt execution module"
        return ret
    result = __salt__["tnsr.manage_api"](
        user, password, host, port=port, api_key=api_key, verify_ssl=verify_ssl
    )
    ret["changes"]["managed"] = result["name"]
    if not result["result"]:
        ret["result"] = False
        ret["comment"] = "Failed to add TNSR API to the Salt execution module"
    return ret
