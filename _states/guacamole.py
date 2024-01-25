### Guacamole State Module
"""Guacamole is State Module"""
import json

__virtualname__ = "guacamole"

def __virtual__():
    return __virtualname__

def update_user_details(name, host, username, password,**kwargs):
    """Updatind User Details""" 

    ret = {"name": name, "result": False, "changes": {}, "comment": ""}

    if "test" not in kwargs:
        kwargs["test"] = __opts__.get("test", False)

    current_state = json.loads(__salt__["guacamole.detail_user"](host, "mysql", username, password, kwargs.get("guac_username")))

    current_state = {
        "username": current_state['username'],
            "attributes": {
                "guac-full-name": current_state['attributes'].get("guac-full-name"),
                "guac-email-address": current_state['attributes'].get("guac-email-address"),
                "guac-organization": current_state['attributes'].get("guac-organization"),
            },
        }

    new_state = {
    "username": kwargs.get("guac_username"),
            "attributes": {
                "guac-full-name": kwargs.get("guac_full_name", None),
                "guac-email-address": kwargs.get("guac_email", None),
                "guac-organization": kwargs.get("guac_org", None),
            },
        }

    if current_state == new_state:
        ret["result"] = True
        ret["comment"] = "System in correct state"
        return ret

# if state does need to be changed. Check if running
# in ``test=true`` mode.
    if __opts__["test"] == True:
        ret["comment"] = f'The state of "{name}" will be changed.'
        ret["changes"] = {
            "old": current_state,
            "new": new_state,
        }
# Return ``None`` when running with ``test=true``.
        ret["result"] = None

        return ret

# Finally, make the actual change and return the result.
    new_state = __salt__["guacamole.update_user"](host, username, password, new_state.get("username"), new_state.get("attributes"))
    new_state = json.loads(__salt__["guacamole.detail_user"](host,"mysql",username, password, kwargs.get("guac_username")))

    new_state = {
        "username": new_state["username"],
            "attributes": {
                "guac-full-name": new_state['attributes'].get("guac-full-name"),
                "guac-email-address": new_state['attributes'].get("guac-email-address"),
                "guac-organization": new_state['attributes'].get("guac-organization"),
            },
        }

    ret["comment"] = f'The state of "{name}" was changed!'

    ret["changes"] = {
        "old": current_state,
        "new": new_state,
    }

    ret["result"] = True
    return ret

def update_user_password(name, host, username, password, guac_new_password, **kwargs):
    """Updatind User Passwords"""
    ret = {"name": name, "result": False, "changes": {}, "comment": ""}

    if "test" not in kwargs:
        kwargs["test"] = __opts__.get("test", False)

    guac_old_password = kwargs.get("guac_old_password")
    guac_new_password = guac_new_password

    if guac_old_password == guac_new_password:
        ret["result"] = True
        ret["comment"] = "System in correct state"
        return ret

# if state does need to be changed. Check if we're running
# in ``test=true`` mode.
    if __opts__["test"] == True:
        ret["comment"] = f'The state of "{name}" will be changed.'
        ret["changes"] = {
            "old": guac_old_password,
            "new": guac_new_password,
        }

# Return ``None`` when running with ``test=true``.
        ret["result"] = None
        return ret

# Finally, make the actual change and return the result.
    new_password = __salt__["guacamole.update_user_password"](host, "mysql", username, password, kwargs.get("guac_username"), guac_old_password, guac_new_password)
    ret["comment"] = f'The state of "{name}" was changed!'

#Need to find methods to pull password hash

    ret["changes"] = {
        "old": guac_old_password,
        "new": new_password.status_code
    }

    ret["result"] = True

    return ret
