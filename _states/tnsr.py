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

__virtualname__ = 'tnsr'

def __virtual__():
    return __virtualname__

def nat_updated(name, new_tables, **kwargs):
    """
    Ensure that the NAT config is managed by Salt.
    """
    test = kwargs.get("test", __opts__.get("test", False))
    ret = {"name": name, "changes": {}, "result": True, "comment": ""}
    
    # Create TNSR session
    tnsr = __salt__['tnsr.Session'](hostname, cert, key, cacert, headers)

    # Get current NAT mapping tables
    current_tables = json.loads(tnsr.get_nat_mapping_tables())

    # Check if the NAT mapping tables are already managed by Salt
    if current_tables == new_tables:
        ret["comment"] = "NAT config is already managed by Salt"
        return ret

    # Check if test mode is enabled
    if test:
        ret["result"] = None
        ret["comment"] = "NAT config mapping entry would be updated"
        return ret

    # Update NAT config mapping entry
    result = tnsr.update_nat_mapping_tables(new_tables)

    # Check if update was successful
    if not result:
        ret["result"] = False
        ret["comment"] = "Failed to update NAT config mapping entry"
        return ret

    ret["changes"]["updated"] = result
    ret["comment"] = "Successfully updated NAT config mapping entry"
    return ret


def unbound_updated(name, new_zones, **kwargs):
    """
    Ensure that the DNS config is managed by Salt.
    """
    test = kwargs.get("test", __opts__.get("test", False))
    ret = {"name": name, "changes": {}, "result": True, "comment": ""}

    # Create TNSR session
    tnsr = __salt__["tnsr.Session"](hostname, cert, key, cacert, headers)

    # Get current Unbound zones
    current_zones = json.loads(tnsr.get_unbound_local_zones())

    # Check if the Unbound zones are already managed by Salt
    if current_zones == new_zones:
        ret["comment"] = "DNS config is already managed by Salt"
        return ret

    # Check if test mode is enabled
    if test:
        ret["result"] = None
        ret["comment"] = "DNS config mapping entry would be updated"
        return ret

    # Update Unbound zones
    result = tnsr.update_unbound_local_zones(new_zones)

    # Check if update was successful
    if not result:
        ret["result"] = False
        ret["comment"] = "Failed to update DNS config mapping entry"
        return ret
    
    ret["changes"]["updated"] = result
    ret["comment"] = "Successfully updated NAT config mapping entry"
    return ret
