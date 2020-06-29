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

    if "test" not in kwargs:
        kwargs["test"] = __opts__.get("test", False)

    if kwargs["test"]:
        current_description = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/description', **kwargs)
        current_members = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/address', **kwargs)

        if (json.loads(current_description["configuration"])["children"][0]["name"] == description):
        # and
        # (json.loads(current_members["configuration"])["children"][0]["name"] == description)

        ret["result"] = True
        ret["comment"] = str(json.loads(current_members["configuration"])["children"][0]["name"])
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
