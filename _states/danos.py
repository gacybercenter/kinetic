### Danos State Module

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
        results = __salt__["danos.get_full_configuration"](host, username, password, **kwargs)
        ret["result"] = results["result"]
        ret["comment"] = results["comment"]

    return ret
