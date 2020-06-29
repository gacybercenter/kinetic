### Danos State Module
import json

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
        for member in json.loads(current_members)["children"]:
            memberlist.append(member["name"])

        if (json.loads(current_description)["children"][0]["name"] == description
        and
        set(memberlist) == set(values)):

            ret["result"] = True
            ret["comment"] = "The "+name+" resource group is up-to-date"
        else:
            ret["result"] = None
            ret["comment"] = "The "+name+" resource group has required changes"
            ret["changes"] = {"group":name,
                              "current description":json.loads(current_description)["children"][0]["name"],
                              "target description":description,
                              "current members":set(memberlist),
                              "target members":set(values)}
    else:
        current_description = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/description', **kwargs)
        current_members = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/address', **kwargs)

        memberlist = []
        for member in json.loads(current_members)["children"]:
            memberlist.append(member["name"])

        if (json.loads(current_description)["children"][0]["name"] == description
        and
        set(memberlist) == set(values)):


            ret["result"] = True
            ret["comment"] = "The "+name+" resource group is up-to-date"
        else:
            ret["result"] = True
            ret["comment"] = "The "+name+" resource group has been updated"
            ret["changes"] = {"group":name,
                              "old description":json.loads(current_description)["children"][0]["name"],
                              "new description":description,
                              "old members":set(memberlist),
                              "new members":set(values)}
    return ret
