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
        current_members = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/address', **kwargs)

        memberlist = []
        for member in current_members:
            memberlist.append(member["name"])
            
        if (json.loads(current_description["configuration"])["children"][0]["name"] == description):
        # and
        # (json.loads(current_members["configuration"])["children"][0]["name"] == description)

            ret["result"] = True
            ret["comment"] = str(json.loads(current_members["configuration"])["children"])+str(values)
    else:
        current_description = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/description', **kwargs)
        current_members = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/address', **kwargs)

        if json.loads(current_description["configuration"])["children"][0]["name"] == description:
            ret["result"] = True
            ret["comment"] = "Description OK"
        else:
            ret["result"] = True
            ret["comment"] = str(json.loads(current_description["configuration"])["children"])
    return ret
