### nexusproxy State Module
"""nexusproxy is State Module"""
import json

__virtualname__ = "nexusproxy"

def __virtual__():
    return __virtualname__

def update_user_password(name, host, port, username, password, user, new_password, **kwargs):
    '''
    This function is used to change a user password in Nexus Proxy.
    
    @param host: Nexus host ip or dns name to inlude the http:// or https://
    @param port: Nexus listening port
    @param username: Nexus username
    @param password: Nexus password
    @param user: User to change password for
    @param new_password: New password for user
    '''
    ret = {"name": name, "result": False, "changes": {}, "comment": ""}
    if "test" not in kwargs:
        kwargs["test"] = __opts__.get("test", False)
    if __opts__["test"] == True:
        ret["comment"] = f'The state of "{name}" will be changed.'
        ret["changes"] = {
            "old": "",
            "new": f'new password: {new_password} would be set'
        }
        ret["result"] = None
        return ret
    current_users = json.loads(__salt__["nexusproxy.list_users"](host,
                                                                 port,
                                                                 username,
                                                                 password))
    currentUserList = []
    for current_user in current_users:
        currentUserList.append(current_user['userId'])
    if user not in currentUserList:
        ret["comment"] = f'User: "{user}" is not present.'
        ret["result"] = False
        return ret
    new_state = __salt__["nexusproxy.change_user_password"](host,
                                                                       port,
                                                                       username,
                                                                       password,
                                                                       user,
                                                                       new_password)
    if new_state == 204:
        ret["comment"] = f'The state of "{name}" was changed successfully!'
        ret["changes"] = {
            "old": '',
            "new": f'new password: {new_password} | http status code: {new_state}'
        }
        ret["result"] = True
        return ret
    ret["comment"] = f'The state of "{name}" returned status code: {new_state}'
    ret["result"] = False
    return ret
def activate_realms(name, realms, host, port, username, password):
    '''
    This function is used to activate the auth realms if needed
    
    @param host: Nexus host ip or dns name to inlude the http:// or https://
    @param port: Nexus listening port
    @param username: Nexus username
    @param password: Nexus password
    '''
    ret = {"name": name, "realms": realms, "result": False, "changes": {}, "comment": ""}
    current_state = __salt__["nexusproxy.list_active_realms"](host,
                                                                         port,
                                                                         username,
                                                                         password)
    if current_state == realms:
        ret["comment"] = f'Realms: "{current_state}" is already set'
        ret["result"] = True
        return ret
    new_realms = __salt__["nexusproxy.activate_realms"](host,
                                                       port,
                                                       username,
                                                       password,
                                                       realms)
    if new_realms == 201:
        current_realms = json.loads(__salt__["nexusproxy.list_active_realms"](host,
                                                                              port,
                                                                              username,
                                                                              password))
        ret["comment"] = f'Realms: "{current_realms}" have been added!'
        ret["changes"] = {
            "old": '',
            "new": current_state
        }
        ret["result"] = True
        return ret
    ret["comment"] = f'The state of "{realms}" returned status code: {new_realms}'
    ret["result"] = False
    return ret
def add_proxy_repository(name, host, port, username, password, repoType, remoteUrl, test: bool = False, **kwargs):
    '''
    This function is used to add a proxy repository in Nexus Proxy.
    
    @param host: Nexus host ip or dns name to inlude the http:// or https://
    @param port: Nexus listening port
    @param username: Nexus username
    @param password: Nexus password
    @param test: Boolean to test the state
    @param kwargs: Dictionary of repository parameters
    '''
    ret = {"name": name, "result": False, "changes": {}, "comment": ""}
    current_state = __salt__["nexusproxy.list_repository"](host,
                                                                        port,
                                                                        username,
                                                                        password,
                                                                        name)
    if test == True:
        ret["comment"] = f'The state of "{name}" will be changed.'
        ret["changes"] = {
            "old": current_state,
            "new": f'new repository: {name} would be added',
        }
        ret["result"] = None
        return ret
    if current_state['name'] == name:
        ret["comment"] = f'Repository: "{name}" is already present.'
        ret["result"] = True
        return ret
    new_state = __salt__["nexusproxy.add_proxy_repository"](host,
                                                            port,
                                                            username,
                                                            password,
                                                            name,
                                                            repoType,
                                                            remoteUrl,
                                                            **kwargs)
    if new_state == 201:
        repository = json.loads(__salt__["nexusproxy.list_repository"](host,
                                                                        port,
                                                                        username,
                                                                        password,
                                                                        name))
        ret["comment"] = f'Repository: "{name}" was added successfully!'
        ret["changes"] = {
            "old": '',
            "new": repository
        }
        ret["result"] = True
        return ret
    ret["comment"] = f'The state of "{name}" returned status code: {new_state}'
    ret["result"] = False
    return ret
