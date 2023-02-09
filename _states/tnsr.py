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

    # Checks for "test" and "delete" keyword arguments, default to False if not provided
    test = kwargs.get("test", __opts__.get("test", False))
    remove = kwargs.get("delete", __opts__.get("remove", False))

    ret = {"name": name, "changes": {}, "result": True, "comment": ""}
    
    # Get current NAT tables
    current_tables = __salt__["tnsr.nat_tables_request"]("GET", 
                                                        cert, 
                                                        key, 
                                                        cacert=cacert)

    # Parse current JSON and new YAML data
    current_tables = json.loads(current_tables)
    new_tables = yaml.safe_load(new_tables)

    merged_tables = __salt__["tnsr.merge_tables"](current_tables, 
                                                new_tables, 
                                                remove)

    if merged_tables == current_tables:
        ret["comment"] = "NAT tables are already managed by Salt"
        return ret

    # If test, return old and new tables
    if test:
        ret["changes"] = {
            "old": current_tables,
            "new": merged_tables,
        }
        ret["comment"] = "NAT tables would have been updated"
        ret["result"] = None
        return ret

    # Update NAT mapping tables
    __salt__["tnsr.nat_tables_request"]("PUT", 
                                        cert, 
                                        key, 
                                        cacert=cacert, 
                                        payload=json.dumps(merged_tables))

    # Return successful update
    ret["changes"] = {
            "old": current_tables,
            "new": merged_tables,
        }
    ret["comment"] = "Successfully updated NAT tables"
    ret["result"] = True
    return ret


def unbound_updated(name, 
                    new_zones, 
                    cert, 
                    key, 
                    cacert=False, 
                    **kwargs):

    # Checks for "test" and "delete" keyword arguments, default to False if not provided
    test = kwargs.get("test", __opts__.get("test", False))
    remove = kwargs.get("delete", __opts__.get("remove", False))

    ret = {"name": name, "changes": {}, "result": True, "comment": ""}
    
    # Get current NAT tables
    current_zones = __salt__["tnsr.unbound_zones_request"]("GET", 
                                                            cert, 
                                                            key, 
                                                            cacert=cacert)

    # Parse current JSON and new YAML data
    current_zones = json.loads(current_zones)
    new_zones = yaml.safe_load(new_zones)

    merged_zones = __salt__["tnsr.merge_zones"](current_zones, 
                                                new_zones, 
                                                remove)

    if merged_zones == current_zones:
        ret["comment"] = "NAT tables are already managed by Salt"
        return ret

    # If test, return old and new zones
    if test:
        ret["changes"] = {
            "old": current_zones,
            "new": merged_zones
        }
        ret["comment"] = "NAT tables would have been updated"
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
    ret["comment"] = "Successfully updated NAT tables"
    ret["result"] = True
    return ret