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
        current_state = __salt__["guacamole.detail_user"](guac_user)

    current_state_1 = {
        "username": current_state['username'],
            "attributes": {
                "guac-full-name": current_state['attributes'].get("guac-full-name"),
                "guac-email-address": current_state['attributes'].get("guac-email-address"),
                "guac-organization": current_state['attributes'].get("guac-organization"),
            },
        }

    new_state = {
        "username": guac_user,
            "attributes": {
                "guac-full-name": guac_full_name,
                "guac-email-address": guac_email,
                "guac-organization": guac_org,
            },
        }

    if current_state_1 == new_state:
        ret["result"] = True
        ret["comment"] = "System in correct state"
        return ret
        

    # if state does need to be changed. Check if we're running
    # in ``test=true`` mode.
    if __opts__["test"] == True:
        ret["comment"] = 'The state of "{0}" will be changed.'.format(guac_user)
        ret["changes"] = {
            "old": current_state,
            "new": "updated user",
        }
        
        detail_user = ret["changes"].update({"guac_user": {"old": current_state, "new": new_state}})

        # Return ``None`` when running with ``test=true``.
        ret["result"] = None

        return ret

    # Finally, make the actual change and return the result.
    new_state = __salt__["guacamole.update_user"](guac_user, attributes={"guac-full-name": guac_full_name, 
    "guac-email-address": guac_email, "guac-organization": guac_org})

    ret["comment"] = 'The state of "{0}" was changed!'.format(name)

    ret["changes"] = {
        "old": current_state,
        "new": new_state,
    }

    ret["result"] = True

    return ret 