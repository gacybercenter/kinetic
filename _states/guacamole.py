### Guacamole State Module
import json
from urllib.parse import quote

__virtualname__ = "guacamole"

def __virtual__():
    return __virtualname__

def update_user(name,
                host,
                username,
                password,
                **kwargs):
    
    ret = {"name": name, "result": False, "changes": {}, "comment": ""}
    
    if "test" not in kwargs:
        kwargs["test"] = __opts__.get("test", False)

    ### If test is specified:
    ### the same, return changes dict.
    if kwargs["test"]:
        current_state = __salt__["guacamole.detail_user"](username)

    new_state = {
        "username": "",
        "attributes": {
            "guac-full-name": null,
            "access-window-start": null,
            "guac-organization": null,
            "access-window-end": null,
            "disabled": null,
        },
        
    }

    if current_state == new_state:
        ret["result"] = True
        ret["comment"] = "System in correct state"
        return ret
        

    # if state does need to be changed. Check if we're running
    # in ``test=true`` mode.
    if __opts__["test"] == True:
        ret["comment"] = 'The state of "{0}" will be changed.'.format(name)
        ret["changes"] = {
            "old": current_state,
            "new": "Description of the new state",
        }
   #detail_user = ret["changes"].update({"name": {"old": "", "new": "name-1"}})

   