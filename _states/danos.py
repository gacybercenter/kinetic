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
        ret["result"] = True
        ret["comment"] = "The resource group is alrady correctly configured"
    else:
        current_description = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name, **kwargs)
        current_members = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/address', **kwargs)

        if json.loads(currnet_description["configuration"])["children"] == description:
            ret["result"] = True
            ret["comment"] = "Description OK"
        else:
            ret["result"] = True
            ret["comment"] = json.loads(currnet_description["configuration"])["children"]
    return ret
