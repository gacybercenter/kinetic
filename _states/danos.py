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

### Danos State Module
import json
from urllib.parse import quote

__virtualname__ = 'danos'

def __virtual__():
    return __virtualname__

def set_resourcegroup(name,
                      type,
                      description,
                      values,
                      username,
                      password,
                      host,
                      **kwargs):

    groupmap = {"address-group": "address",
                "dscp-group": "dscp",
                "port-group": "port",
                "protocol-group": "protocol"}

    ret = {"name": name, "result": False, "changes": {}, "comment": ""}

    ### If test isn't specified, assume test=false
    if "test" not in kwargs:
        kwargs["test"] = __opts__.get("test", False)

    ### If test is specified:
    ### Get current description and members and compare to target description
    ### and members.  If the same, return result=true and no changes.  If not
    ### the same, return changes dict.
    if kwargs["test"]:
        current_description = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/description', **kwargs)
        current_members = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/'+groupmap[type], **kwargs)

        memberlist = []
        if "children" in current_members:
            for member in json.loads(current_members)["children"]:
                memberlist.append(member["name"])

        descr = ""
        if "children" in current_description:
            descr = json.loads(current_description)["children"][0]["name"]

        if (descr == description and set(memberlist) == set(values)):

            ret["result"] = True
            ret["comment"] = "The "+name+" resource group is up-to-date"
        else:
            ret["result"] = None
            ret["comment"] = "The "+name+" resource group has required changes"
            ret["changes"] = {"group":name,
                              "current description":descr,
                              "target description":description,
                              "current members":set(memberlist),
                              "target members":set(values)}
    else:
        current_description = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/description', **kwargs)
        current_members = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/'+groupmap[type], **kwargs)

        memberlist = []
        if "children" in current_members:
            for member in json.loads(current_members)["children"]:
                memberlist.append(member["name"])

        descr = ""
        if "children" in current_description:
            descr = json.loads(current_description)["children"][0]["name"]


        if (descr == description and set(memberlist) == set(values)):
        ### no changes needed
            ret["result"] = True
            ret["comment"] = "The "+name+" resource group is up-to-date"

        else:
        ### Changes are needed
        ### Create session to be used throughout
            location = __salt__["danos.make_session"](host, username, password)
            __salt__["danos.delete_configuration"](host, username, password, '/resources/group/'+type+'/'+name, location, **kwargs)
            __salt__["danos.set_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/description/'+quote(description), location, **kwargs)
            for value in values:
                __salt__["danos.set_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/'+groupmap[type]+'/'+value, location, **kwargs)
            __salt__["danos.commit_configuration"](host, username, password, location)
            __salt__["danos.delete_session"](host, username, password, location)

            ret["result"] = True
            ret["comment"] = "The "+name+" resource group has been updated"
            ret["changes"] = {"group":name,
                              "old description":descr,
                              "new description":description,
                              "old members":set(memberlist),
                              "new members":set(values)}
    return ret

def set_statichostmapping(name,
                          address,
                          username,
                          password,
                          host,
                          aliases=None,
                          **kwargs):

    ret = {"name": name, "result": False, "changes": {}, "comment": ""}

    ### If test isn't specified, assume test=false
    if "test" not in kwargs:
        kwargs["test"] = __opts__.get("test", False)

    ### If test is specified:
    ### Get current description and members and compare to target description
    ### and members.  If the same, return result=true and no changes.  If not
    ### the same, return changes dict.
    if kwargs["test"]:
        current_address = __salt__["danos.get_configuration"](host, username, password, '/system/static-host-mapping/host-name/'+name+'/inet', **kwargs)
        current_aliases = __salt__["danos.get_configuration"](host, username, password, '/system/static-host-mapping/host-name/'+name+'/alias', **kwargs)

        aliaslist = []
        if "children" in current_aliases:
            for alias in json.loads(current_aliases)["children"]:
                aliaslist.append(alias["name"])

        addr = ""
        if "children" in current_address:
            addr = json.loads(current_address)["children"][0]["name"]

        if (addr == address and set(aliaslist) == set(aliases)):

            ret["result"] = True
            ret["comment"] = "The "+name+" static-host-mapping is up-to-date"
        else:
            ret["result"] = None
            ret["comment"] = "The "+name+" static-host-mapping has required changes"
            ret["changes"] = {"hostname":name,
                              "current address":addr,
                              "target address":address,
                              "current aliases":set(aliaslist),
                              "target aliases":set(aliases)}
    else:
        current_address = __salt__["danos.get_configuration"](host, username, password, '/system/static-host-mapping/host-name/'+name+'/inet', **kwargs)
        current_aliases = __salt__["danos.get_configuration"](host, username, password, '/system/static-host-mapping/host-name/'+name+'/alias', **kwargs)

        aliaslist = []
        if "children" in current_aliases:
            for alias in json.loads(current_aliases)["children"]:
                aliaslist.append(alias["name"])

        addr = ""
        if "children" in current_address:
            addr = json.loads(current_address)["children"][0]["name"]

        if (addr == address and set(aliaslist) == set(aliases)):
        ### no changes needed
            ret["result"] = True
            ret["comment"] = "The "+name+" static-host-mapping is up-to-date"
        else:
        ### Changes are needed
        ### Create session to be used throughout
            location = __salt__["danos.make_session"](host, username, password)
            __salt__["danos.delete_configuration"](host, username, password, '/system/static-host-mapping/host-name/'+name, location, **kwargs)
            __salt__["danos.set_configuration"](host, username, password, '/system/static-host-mapping/host-name/'+name+'/inet/'+address, location, **kwargs)
            for alias in aliases:
                __salt__["danos.set_configuration"](host, username, password, '/system/static-host-mapping/host-name/'+name+'/alias/'+alias, location, **kwargs)
            __salt__["danos.commit_configuration"](host, username, password, location)
            __salt__["danos.reset_dns_forwarding_cache"](host, username, password)
            __salt__["danos.delete_session"](host, username, password, location)

            ret["result"] = True
            ret["comment"] = "The "+name+" static-host-mapping has been updated"
            ret["changes"] = {"hostname":name,
                              "current address":addr,
                              "target address":address,
                              "current aliases":set(aliaslist),
                              "target aliases":set(aliases)}
    return ret
