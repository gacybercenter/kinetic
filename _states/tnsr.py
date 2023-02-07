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
                new_tables, 
                cert, 
                key, 
                cacert=False, 
                **kwargs):

    # Check if "test" is a keyword argument, default to False if not provided
    test = kwargs.get("test", __opts__.get("test", False))
    ret = {"name": name, "changes": {}, "result": True, "comment": ""}
    
    # Get current NAT tables
    current_tables = __salt__["tnsr.nat_tables_request"]("GET", 
                                                        cert, 
                                                        key, 
                                                        cacert=cacert)

    try:
        # Try to parse current JSON and new YAML data
        current_tables = json.loads(current_tables)
        new_tables = yaml.safe_load(new_tables)
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to parse the JSON or YAML NAT data. Error: {e}"
        return ret

    # Check if the NAT mapping tables are already managed by Salt
    if current_tables == new_tables:
        ret["comment"] = "NAT tables are already managed by Salt"
        return ret

    # Check if test mode is enabled
    if test:
        ret["result"] = None
        ret["comment"] = "NAT tables would have been updated"
        return ret

    # Update NAT config mapping entry
    result = __salt__["tnsr.nat_tables_request"]("PUT", 
                                                cert, 
                                                key, 
                                                cacert=cacert, 
                                                payload=new_tables)

    # Check if update was successful
    if not result:
        ret["result"] = False
        ret["comment"] = "Failed to update NAT tables"
        return ret

    ret["changes"]["updated"] = result
    ret["comment"] = "Successfully updated NAT tables"
    return ret


def unbound_updated(name, 
                    new_zones, 
                    cert, 
                    key, 
                    cacert=False, 
                    **kwargs):

    # Check if "test" is a keyword argument, default to False if not provided
    test = kwargs.get("test", __opts__.get("test", False))
    ret = {"name": name, "changes": {}, "result": True, "comment": ""}

    # Get current Unbound zones
    current_zones = __salt__["tnsr.unbound_zones_request"]("GET", 
                                                            cert, 
                                                            key, 
                                                            cacert=cacert)
    
    try:
        # Try to parse current JSON and new YAML data
        current_zones = json.loads(current_zones)
        new_zones = yaml.safe_load(new_zones)
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to parse the JSON or YAML DNS data. Error: {e}"
        return ret

    # Check if the Unbound zones are already managed by Salt
    if current_zones == new_zones:
        ret["comment"] = "DNS mapping is already managed by Salt"
        return ret

    # Check if test mode is enabled
    if test:
        ret["result"] = None
        ret["comment"] = "DNS mapping would have been updated"
        return ret

    # Update Unbound zones
    result = __salt__["tnsr.unbound_zones_request"]("PUT", 
                                                    cert, 
                                                    key, 
                                                    cacert=cacert, 
                                                    payload=new_zones)

    # Check if update was successful
    if not result:
        ret["result"] = False
        ret["comment"] = "Failed to update DNS mapping"
        return ret
    
    ret["changes"]["updated"] = result
    ret["comment"] = "Successfully updated DNS mapping"
    return ret
