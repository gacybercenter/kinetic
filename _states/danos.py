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
        description = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name, **kwargs)
        members = __salt__["danos.get_configuration"](host, username, password, '/resources/group/'+type+'/'+name+'/address', **kwargs)

        if json.loads(description["configuration"])["name"] == description
            ret["result"] = results["result"]
            ret["comment"] = results["Description OK"]
        else:
            ret["result"] = results["result"]
            ret["comment"] = results["Description Not OK"]
    return ret
