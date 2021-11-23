## Copyright 2020 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
## guacamole module - primarily used for provisioning users and connection
## could potentially be fleshed out and become formal fully-featured
## salt module

import socket
import requests
import urllib3
import json

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
socket.setdefaulttimeout(0.5)

__virtualname__ = "guacamole"

def __virtual__():
    return __virtualname__
    
# Documentation for API: https://github.com/ridvanaltun/guacamole-rest-api-documentation/tree/master/docs

class Session:
    def __init__(self, host: str, data_source: str, username: str, password: str):
        self.host = host
        self.username = username
        self.password = password
        self.data_source = data_source
        self.token = self.generate_token()
        self.params = {"token": self.token}

    def generate_token(self):
        """Returns a token"""

        return requests.post(
            f"{self.host}/api/tokens",
            data={"username": self.username, "password": self.password},
            verify=False,
            headers={"Content-Type": "application/x-www-form-urlencoded"}
        ).json()['authToken']

    def delete_token(self):
        """Deletes a token"""

        return requests.delete(
            f"{self.host}/api/tokens/{self.token}",
            params=self.params,
            verify=False,
        )

    def list_schema_users(self):
        """Returns schema for user attributes"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/schema/userAttributes",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def list_schema_groups(self):
        """Returns schema for group attributes"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/schema/userGroupAttributes",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def list_schema_connections(self):
        """Returns schema for connection attributes"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/schema/connectionAttributes",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def list_schema_sharing(self):
        """Returns schema for sharing attributes"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/schema/sharingProfileAttributes",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def list_schema_connection_group(self):
        """Returns schema for connection group attributes"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/schema/connectionGroupAttributes",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def list_schema_protocols(self):
        """Returns schema for protocols attributes"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/schema/protocols",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def list_patches(self):
        """
        Returns patches
        TODO: NEED TO EXPLORE FURTHER API CAPABILITIES FROM THIS PATH
        """

        return json.dumps(requests.get(
            f"{self.host}/api/patches",
            params=self.params,
            verify=False
        ).json(), indent=2)


    def list_languages(self):
        """Returns available locales"""

        return json.dumps(requests.get(
            f"{self.host}/api/languages",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def detail_extensions(self):
        """
        Returns details for installed extensions
        TODO: VALIDATE FUNCTION OPERATES
        """

        return json.dumps(requests.get(
            f"{self.host}/api/session/ext/{self.data_source}",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def list_history_users(self):
        """Returns user history"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/history/users",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def list_history_connections(self):
        """Returns user connections"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/history/connections",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def list_users(self):
        """Returns users"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/users",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def detail_user(self, username: str):
        """Returns users details"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/users/{username}",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def detail_user_permissions(self, username: str):
        """Returns users permissions"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/users/{username}/permissions",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def detail_user_effective_permissions(self, username: str):
        """Returns users efffective permissions"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/users/{username}/effectivePermissions",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def detail_user_groups(self, username: str):
        """Returns users groups"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/users/{username}/userGroups",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def detail_user_history(self, username: str):
        """Returns users history"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/users/{username}/history",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def detail_self(self):
        """Returns current user details"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/self",
            params=self.params,
            verify=False
        ).json(), indent=2)

    def create_user(self, username: str, password: str, attributes: dict = {}):
        """Creates user"""

        return requests.post(
            f"{self.host}/api/session/data/{self.data_source}/users",
            headers={"Content-Type": "application/json"},
            verify=False,
            params=self.params,
            json={
                "username": username,
                "password": password,
                "attributes": {
                        "disabled": attributes.get("disabled", ""),
                        "expired": attributes.get("expired", ""),
                        "access-window-start": attributes.get("access-window-start", ""),
                        "access-window-end": attributes.get("access-window-end", ""),
                        "valid-from": attributes.get("valid-from", ""),
                        "valid-until": attributes.get("valid-until", ""),
                        "timezone": attributes.get("timezone", ""),
                        "guac-full-name": attributes.get("guac-full-name", ""),
                        "guac-organization": attributes.get("guac-organization", ""),
                        "guac-organizational-role": attributes.get("guac-organizational-role", "")
                },
            }
        )

    def update_user(self, username: str, attributes: dict = {}):
        """Updates a user"""

        return requests.put(
            f"{self.host}/api/session/data/{self.data_source}/users/{username}",
            headers={"Content-Type": "application/json"},
            params=self.params,
            json={
                "username": username,
                "attributes": {
                    "guac-email-address": attributes.get("guac-email-address", None),
                    "guac-organizational-role": attributes.get("guac-organizational-role", None),
                    "guac-full-name": attributes.get("guac-full-name", None),
                    "expired": attributes.get("expired", ""),
                    "timezone": attributes.get("timezone", None),
                    "access-window-start": attributes.get("access-window-start", ""),
                    "guac-organization": attributes.get("guac-organization", None),
                    "access-window-end": attributes.get("access-window-end", ""),
                    "disabled": attributes.get("disabled", ""),
                    "valid-until": attributes.get("valid-until", ""),
                    "valid-from": attributes.get("valid-from", "")
                }
            },
            verify=False,
        )

    def update_user_password(self, username: str, oldpassword: str, newpassword: str):
        """Updates a user Password"""

        return requests.put(
            f"{self.host}/api/session/data/{self.data_source}/users/{username}/password",
            headers={"Content-Type": "application/json"},
            params=self.params,
            json={
                "oldPassword": oldpassword,
                "newPassword": newpassword
            },
            verify=False,
        )

    def update_user_group(self, username: str, groupname: str, operation: str = "add"):
        """Assign to or Remove user from group"""

        if operation == "add" or operation == "remove":
            return requests.patch(
                f"{self.host}/api/session/data/{self.data_source}/users/{username}/userGroups",
                headers={"Content-Type": "application/json"},
                params=self.params,
                json=[
                    {
                        "op": operation,
                        "path": "/",
                        "value": groupname
                    }
                ],
                verify=False,
            )
        else:
            return "Invalid Operation, requires (add or remove)"

    def update_user_connection(self, username: str, connectionid: str, operation: str = "add", isgroup: bool = False):
        """
        Change a user Connections
        TODO: VALIDATE FUNCTION OPERATES
        """

        if not isgroup:
            path = f"/connectionPermissions/{connectionid}"
        elif isgroup:
            path = f"/connectionGroupPermissions/{connectionid}"

        if operation == "add" or operation == "remove":
            return requests.patch(
                f"{self.host}/api/session/data/{self.data_source}/users/{username}/permissions",
                headers={"Content-Type": "application/json"},
                params=self.params,
                json=[
                    {
                        "op": operation,
                        "path": path,
                        "value": "READ"
                    }
                ],
                verify=False,
            )
        else:
            return "Invalid Operation, requires (add or remove)"

    def update_user_permissions(self, username: str, operation: str = "add", cuser: bool = False, cusergroup: bool = False, cconnect: bool = False, cconnectgroup: bool = False, cshare: bool = False, admin: bool = False):
        """Change a user Connections"""

        path = f"/userPermissions/{username}"

        permissions = []

        permissions.append({
                "op": operation,
                "path": path,
                "value": "UPDATE"
                })

        if cuser:
            permissions.append({
                            "op": operation,
                            "path": "/systemPermissions",
                            "value": "CREATE_USER"
                        })

        if cusergroup:
            permissions.append({
                        "op": operation,
                        "path": "/systemPermissions",
                        "value": "CREATE_USER_GROUP"
                    })

        if cconnect:
            permissions.append({
                        "op": operation,
                        "path": "/systemPermissions",
                        "value": "CREATE_CONNECTION"
                    })

        if cconnectgroup:
            permissions.append({
                        "op": operation,
                        "path": "/systemPermissions",
                        "value": "CREATE_CONNECTION_GROUP"
                    })

        if cshare:
            permissions.append({
                        "op": operation,
                        "path": "/systemPermissions",
                        "value": "CREATE_SHARING_PROFILE"
                    })

        if admin:
            permissions.append({
                        "op": operation,
                        "path": "/systemPermissions",
                        "value": "ADMINISTER"
                    })

        if operation == "add" or operation == "remove":
            return requests.patch(
                f"{self.host}/api/session/data/{self.data_source}/users/{username}/permissions",
                headers={"Content-Type": "application/json"},
                params=self.params,
                json=permissions,
                verify=False,
            )
        else:
            return "Invalid Operation, requires (add or remove)"

    def delete_user(self, username: str):
        """Deletes user"""

        return requests.delete(
            f"{self.host}/api/session/data/{self.data_source}/users/{username}",
            params=self.params,
            verify=False,
        )

    def list_usergroups(self):
        """Returns user groups"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/userGroups",
            params=self.params,
            verify=False,
        ).json(), indent=2)

    def detail_usergroup(self, groupname: str):
        """Returns user groups"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/userGroups/{groupname}",
            params=self.params,
            verify=False,
        ).json(), indent=2)

    def update_usergroup_member(self, username: str, groupname: str, operation: str = "add"):
        """Assign to or Remove user from group"""

        if operation == "add" or operation == "remove":
            return requests.patch(
                f"{self.host}/api/session/data/{self.data_source}/userGroups/{groupname}/memberUsers",
                headers={"Content-Type": "application/json"},
                params=self.params,
                json=[
                    {
                        "op": operation,
                        "path": "/",
                        "value": username
                    }
                ],
                verify=False,
            )
        else:
            return "Invalid Operation, requires (add or remove)"

    def update_usergroup_membergroup(self, identifier: int, groupname: str, operation: str = "add"):
        """Assign to or Remove group from group"""

        if operation == "add" or operation == "remove":
            return requests.patch(
                f"{self.host}/api/session/data/{self.data_source}/userGroups/{groupname}/memberUserGroup",
                headers={"Content-Type": "application/json"},
                params=self.params,
                json=[
                    {
                        "op": operation,
                        "path": "/",
                        "value": str(identifier)
                    }
                ],
                verify=False,
            )
        else:
            return "Invalid Operation, requires (add or remove)"

    def update_usergroup_parentgroup(self, identifier: int, groupname: str, operation: str = "add"):
        """Assign to or Remove group from group"""

        if operation == "add" or operation == "remove":
            return requests.patch(
                f"{self.host}/api/session/data/{self.data_source}/userGroups/{groupname}/userGroups",
                headers={"Content-Type": "application/json"},
                params=self.params,
                json=[
                    {
                        "op": operation,
                        "path": "/",
                        "value": str(identifier)
                    }
                ],
                verify=False,
            )
        else:
            return "Invalid Operation, requires (add or remove)"

    def update_usergroup_permissions(self, groupname: str, operation: str = "add", cuser: bool = False, cusergroup: bool = False, cconnect: bool = False, cconnectgroup: bool = False, cshare: bool = False, admin: bool = False):
        """Update permissions of user group"""

        permissions = []

        permissions.append({
                "op": operation,
                "path": f"/connectionPermissions/{groupname}",
                "value": "READ"
                })

        if cuser:
            permissions.append({
                            "op": operation,
                            "path": "/systemPermissions",
                            "value": "CREATE_USER"
                        })

        if cusergroup:
            permissions.append({
                        "op": operation,
                        "path": "/systemPermissions",
                        "value": "CREATE_USER_GROUP"
                    })

        if cconnect:
            permissions.append({
                        "op": operation,
                        "path": "/systemPermissions",
                        "value": "CREATE_CONNECTION"
                    })

        if cconnectgroup:
            permissions.append({
                        "op": operation,
                        "path": "/systemPermissions",
                        "value": "CREATE_CONNECTION_GROUP"
                    })

        if cshare:
            permissions.append({
                        "op": operation,
                        "path": "/systemPermissions",
                        "value": "CREATE_SHARING_PROFILE"
                    })

        if admin:
            permissions.append({
                        "op": operation,
                        "path": "/systemPermissions",
                        "value": "ADMINISTER"
                    })

        if operation == "add" or operation == "remove":
            return requests.patch(
                f"{self.host}/api/session/data/{self.data_source}/userGroups/{groupname}/permissions",
                headers={"Content-Type": "application/json"},
                params=self.params,
                json=permissions,
                verify=False,
            )
        else:
            return "Invalid Operation, requires (add or remove)"

    def update_usergroup_connection(self, connection_id: int, groupname: str, operation: str = "add"):
        """Assign to or Remove connection from group"""

        if operation == "add" or operation == "remove":
            return requests.patch(
                f"{self.host}/api/session/data/{self.data_source}/userGroups/{groupname}/permissions",
                headers={"Content-Type": "application/json"},
                params=self.params,
                json=[
                    {
                        "op": operation,
                        "path": f"/connectionPermissions/{str(connection_id)}",
                        "value": "READ"
                    }
                ],
                verify=False,
            )
        else:
            return "Invalid Operation, requires (add or remove)"

    def create_usergroup(self, groupname: str, attributes: dict = {}):
        """Creates a user group"""

        return requests.post(
            f"{self.host}/api/session/data/{self.data_source}/userGroups",
            headers={"Content-Type": "application/json"},
            params=self.params,
            json={
                "identifier": groupname,
                "attributes": {
                    "disabled": attributes.get("disabled", "")
                }
            },
            verify=False,
        )

    def update_usergroup(self, groupname: str, attributes: dict = {}):
        """Updates a user group"""
        
        return requests.put(
            f"{self.host}/api/session/data/{self.data_source}/userGroups/{groupname}",
            headers={"Content-Type": "application/json"},
            params=self.params,
            json={
                "identifier": groupname,
                "attributes": {
                    "disabled": attributes.get("disabled", "")
                }
            },
            verify=False,
        )

    def delete_usergroup(self, user_group: str):
        """Deletes a user group"""

        return requests.delete(
            f"{self.host}/api/session/data/{self.data_source}/userGroups/{user_group}",
            params=self.params,
            verify=False,
        )

    def list_tunnels(self):
        """Returns tunnels"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/tunnels",
            verify=False,
            params=self.params,
        ).json(), indent=2)

    def detail_tunnels(self, tunnel_id: int):
        """Returns tunnels"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/tunnels/{str(tunnel_id)}/activeConnection/connection/sharingProfiles",
            verify=False,
            params=self.params,
        ).json(), indent=2)

    def list_connections(self, active: bool = False):
        """
        NOTE: Returns connections or active connections
        * @params active (boolean value) toggles viewing active connections
        """

        if active:
            host = f"{self.host}/api/session/data/{self.data_source}/activeConnections"
        else:
            host = f"{self.host}/api/session/data/{self.data_source}/connections"

        return json.dumps(requests.get(
            host,
            verify=False,
            params=self.params,
        ).json(), indent=2)

    def detail_connection(self, identifier: int, option: str = None):
        """
        NOTE: Returns connection details and parameters
        * @params option (None, params, history, sharing)
        """

        if not option:
            host = f"{self.host}/api/session/data/{self.data_source}/connections/{str(identifier)}"
        elif option == "params":
            host = f"{self.host}/api/session/data/{self.data_source}/connections/{str(identifier)}/parameters"
        elif option == "history":
            host = f"{self.host}/api/session/data/{self.data_source}/connections/{str(identifier)}/history"
        elif option == "sharing":
            host = f"{self.host}/api/session/data/{self.data_source}/connections/{str(identifier)}/sharingProfiles"
        else:
            return "Invalid option, requires no entry or (params, history, or sharing)"

        return json.dumps(requests.get(
            host,
            verify=False,
            params=self.params,
        ).json(), indent=2)

    def kill_active_connection(self, connection_id: str):
        """Kill an active connection to a hosted system"""

        return requests.patch(
            f"{self.host}/api/session/data/{self.data_source}/activeConnections",
            headers={"Content-Type": "application/json"},
            params=self.params,
            json=[
                {
                    "op": "remove",
                    "path": f"/{connection_id}"
                }
            ],
            verify=False,
        )

    def create_connection(self, type: str, name: str, parent_identifier: int, parameters: dict = {}, attributes: dict = {}):
        """
        Creates an SSH connection
        parent_identifier is required if placing in a specific connection group
        parameters = {"hostname": "", "port": "", "username": "", "password": ""}
        attributes = {"max-connections": "", "max-connections-per-user": "" }
        """
        network = {
            "hostname": parameters.get("hostname", ""),
            "port": parameters.get("port", ""),
        }
        network_ssh = {
            "hostname": parameters.get("hostname", ""),
            "port": parameters.get("port", ""),
            "host-key": parameters.get("host-key", ""),
        }
        authentication_general = {
            "username": parameters.get("username", ""),
            "password": parameters.get("password", ""),
        }
        authentication_telnet = {
            "username-regex": parameters.get("username-regex", ""),
            "password-regex": parameters.get("password-regex", ""),
            "login-success-regex": parameters.get("login-success-regex", ""),
            "login-failure-regex": parameters.get("login-failure-regex", ""),
        }
        authentication_ssh = {
            "host-key": parameters.get("host-key", ""),
            "private-key": parameters.get("private-key", ""),
        }
        display_vnc = {
            "read-only": parameters.get("read-only", ""),
            "swap-red-blue": parameters.get("swap-red-blue", ""),
            "cursor": parameters.get("cursor", ""),
            "color-depth": parameters.get("color-depth", ""),
        }
        display_rdp = {
            "width": parameters.get("width", ""),
            "height": parameters.get("height", ""),
            "dpi": parameters.get("dpi", ""),
            "resize-method": parameters.get("resize-method", ""),
            "read-only": parameters.get("read-only", ""),
            "color-depth": parameters.get("color-depth", ""),
        }
        display_terminal = {
            "color-scheme": parameters.get("color-scheme", ""),
            "font-name": parameters.get("font-name", ""),
            "font-size": parameters.get("font-size", ""),
            "scrollback": parameters.get("scrollback", ""),
            "read-only": parameters.get("read-only", ""),
        }
        terminal_behaviour = {
            "backspace": parameters.get("backspace", ""),
            "terminal-type": parameters.get("terminal-type", ""),
        }
        typescript = {
            "create-typescript-path": parameters.get("create-typescript-path", ""),
            "typescript-path": parameters.get("typescript-path", ""),
            "typescript-name": parameters.get("typescript-name", ""),
        }
        clipboard_graphical = {
            "clipboard-encoding": parameters.get("clipboard-encoding", ""),
            "disable-copy": parameters.get("disable-copy", ""),
            "disable-paste": parameters.get("disable-paste", ""),
        }
        clipboard_terminal = {
            "disable-copy": parameters.get("disable-copy", ""),
            "disable-paste": parameters.get("disable-paste", ""),
        }
        session_environment = {
            "timezone": parameters.get("timezone", None),
            "server-alive-interval": parameters.get("server-alive-interval", ""),
            "command": parameters.get("command", ""),
            "locale": parameters.get("locale", ""),
        }
        rdp_gateway = {
            "gateway-port": parameters.get("gateway-port", ""),
            "gateway-hostname": parameters.get("gateway-hostname", ""),
            "gateway-username": parameters.get("gateway-username", ""),
            "gateway-password": parameters.get("gateway-password", ""),
            "gateway-domain": parameters.get("gateway-domain", ""),
        }
        basic_settings = {
            "timezone": parameters.get("timezone", None),
            "initial-program": parameters.get("initial-program", ""),
            "client-name": parameters.get("client-name", ""),
            "console": parameters.get("console", ""),
        }
        vnc_repeater = {
            "dest-host": parameters.get("dest-host", ""),
            "dest-port": parameters.get("dest-port", ""),
        }
        screen_recording = {
            "recording-name": parameters.get("recording-name"),
            "recording-path": parameters.get("recording-path"),
            "recording-exclude-output": parameters.get("recording-exclude-output" ""),
            "recording-exclude-mouse": parameters.get("recording-exclude-mouse", ""),
            "recording-include-keys": parameters.get("recording-include-keys", ""),
            "create-recording-path": parameters.get("create-recording-path", ""),
        }
        sftp = {
            "enable-sftp": parameters.get("enable-sftp", ""),
            "sftp-port": parameters.get("sftp-port", ""),
            "sftp-server-alive-interval": parameters.get("sftp-server-alive-interval", ""),
            "sftp-hostname": parameters.get("sftp-hostname", ""),
            "sftp-host-key": parameters.get("sftp-host-key", ""),
            "sftp-username": parameters.get("sftp-username", ""),
            "sftp-password": parameters.get("sftp-password", ""),
            "sftp-private-key": parameters.get("sftp-private-key", ""),
            "sftp-passphrase": parameters.get("sftp-passphrase", ""),
            "sftp-root-directory": parameters.get("sftp-root-directory", ""),
            "sftp-directory": parameters.get("sftp-directory", ""),
        }
        sftp_ssh = {
            "enable-sftp": parameters.get("enable-sftp", ""),
            "sftp-root-directory": parameters.get("sftp-root-directory", ""),
        }
        audio = {
            "enable-audio": parameters.get("enable-audio", ""),
            "audio-servername": parameters.get("audio-servername", ""),

        }

        if type == "vnc":
            parameters = {
                **network,
                **authentication_general,
                **display_vnc,
                **clipboard_graphical,
                **vnc_repeater,
                **screen_recording,
                **sftp,
                **audio,
            }
        if type == "ssh":
            parameters = {
                **network_ssh,
                **authentication_general,
                **authentication_ssh,
                **display_terminal,
                **clipboard_terminal,
                **session_environment,
                **terminal_behaviour,
                **typescript,
                **screen_recording,
                **sftp_ssh,
            }
        if type == "rdp":
            parameters = {
                **network,
                **rdp_gateway,
                **basic_settings,
                **display_rdp,
            }
        if type == "telnet":
            parameters = {

            }
        if type == "kubernetes":
            parameters = {

            }


        return requests.post(
            f"{self.host}/api/session/data/{self.data_source}/connections",
            headers={"Content-Type": "application/json"},
            params=self.params,
            json={
                "parentIdentifier": str(parent_identifier),
                "name": name,
                "protocol": type,
                "parameters": parameters,
                "attributes": {
                    "max-connections": attributes.get("max-connections", ""),
                    "max-connections-per-user": attributes.get("max-connections-per-user", ""),
                    "weight": attributes.get("weight", ""),
                    "failover-only": attributes.get("failover-only", ""),
                    "guacd-port": attributes.get("guacd-port", ""),
                    "guacd-encryption": attributes.get("guacd-encryption", ""),
                    "guacd-hostname": attributes.get("guacd-hostname", ""),
                }
            },
            verify=False,
        )

    def create_rdp_connection(self, name: str, parent_identifier: str = "ROOT", parameters: dict = {}, attributes: dict = {}):
        """Creates an RDP connection
        parent_identifier is required if placing in a specific connection group
        parameters = {"hostname": "", "port": "", "username": "", "password": "", "security": "any", "ignore-cert": "true"}
        attributes = {"max-connections": "", "max-connections-per-user": "" }
        """






        return requests.post(
            f"{self.host}/api/session/data/{self.data_source}/connections",
            headers={"Content-Type": "application/json"},
            params=self.params,
            json={
                "parentIdentifier": parent_identifier,
                "name": name,
                "protocol": "rdp",
                "parameters": {
                        "port": parameters.get("port", ""),
                        "read-only": parameters.get("read-only", ""),
                        "swap-red-blue": parameters.get("swap-red-blue", ""),
                        "cursor": parameters.get("cursor", ""),
                        "color-depth": parameters.get("color-depth", ""),
                        "clipboard-encoding": parameters.get("clipboard-encoding", ""),
                        "disable-copy": parameters.get("disable-copy", ""),
                        "disable-paste": parameters.get("disabled-paste", ""),
                        "dest-port": parameters.get("dest-port", ""),
                        "recording-exclude-output": parameters.get("recording-exclude-output" ""),
                        "recording-exclude-mouse": parameters.get("recording-exclude-mouse", ""),
                        "recording-include-keys": parameters.get("recording-include-keys", ""),
                        "create-recording-path": parameters.get("create-recording-path", ""),
                        "enable-sftp": parameters.get("enable-sftp", ""),
                        "sftp-port": parameters.get("sftp-port", ""),
                        "sftp-server-alive-interval": parameters.get("sftp-server-alive-interval", ""),
                        "enable-audio": parameters.get("enable-audio", ""),
                        "security": parameters.get("security", ""),
                        "disable-auth": parameters.get("disable-auth", ""),
                        "ignore-cert": parameters.get("ignore-cert", ""),
                        "gateway-port": parameters.get("gateway-port", ""),
                        "gateway-hostname": parameters.get("gateway-hostname", ""),
                        "gateway-username": parameters.get("gateway-username", ""),
                        "gateway-password": parameters.get("gateway-password", ""),
                        "gateway-domain": parameters.get("gateway-domain", ""),
                        "server-layout": parameters.get("server-layout", ""),
                        "timezone": parameters.get("timezone", ""),
                        "console": parameters.get("console", ""),
                        "width": parameters.get("width", ""),
                        "height": parameters.get("height", ""),
                        "dpi": parameters.get("dpi", ""),
                        "resize-method": parameters.get("resize-method", ""),
                        "console-audio": parameters.get("console-audio", ""),
                        "disable-audio": parameters.get("disable-audio", ""),
                        "enable-audio-input": parameters.get("enable-audio-input", ""),
                        "enable-printing": parameters.get("enable-printing", ""),
                        "enable-drive": parameters.get("enable-drive", ""),
                        "create-drive-path": parameters.get("create-drive-path", ""),
                        "enable-wallpaper": parameters.get("enable-wallpaper", ""),
                        "enable-theming": parameters.get("enable-theming", ""),
                        "enable-font-smoothing": parameters.get("enable-font-smoothing", ""),
                        "enable-full-window-drag": parameters.get("enable-full-window-drag", ""),
                        "enable-desktop-composition": parameters.get("enable-desktop-composition", ""),
                        "enable-menu-animations": parameters.get("enable-menu-animations", ""),
                        "disable-bitmap-caching": parameters.get("disable-bitmap-caching", ""),
                        "disable-offscreen-caching": parameters.get("disable-offscreen-caching", ""),
                        "disable-glyph-caching": parameters.get("disable-glyph-caching", ""),
                        "preconnection-id": parameters.get("preconnection-id", ""),
                        "hostname": parameters.get("hostname", ""),
                        "username": parameters.get("username", ""),
                        "password": parameters.get("password", ""),
                        "domain": parameters.get("domain", ""),

                        "initial-program": parameters.get("initial-program", ""),
                        "client-name": parameters.get("client-name", ""),

                        "printer-name": parameters.get("printer-name", ""),
                        "drive-name": parameters.get("drive-name", ""),
                        "drive-path": parameters.get("drive-path", ""),
                        "static-channels": parameters.get("static-channels", ""),

                        "remote-app": parameters.get("remote-app", ""),
                        "remote-app-dir": parameters.get("remote-app-dir", ""),
                        "remote-app-args": parameters.get("remote-app-args", ""),

                        "preconnection-blob": parameters.get("preconnection-blob", ""),
                        "load-balance-info": parameters.get("load-balance-info", ""),
                        "recording-path": parameters.get("recording-path", ""),
                        "recording-name": parameters.get("recording-name", ""),
                        "sftp-hostname": parameters.get("sftp-hostname", ""),
                        "sftp-host-key": parameters.get("sftp-host-key", ""),
                        "sftp-username": parameters.get("sftp-username", ""),
                        "sftp-password": parameters.get("sftp-password", ""),
                        "sftp-private-key": parameters.get("sftp-private-key", ""),
                        "sftp-passphrase": parameters.get("sftp-passphrase", ""),
                        "sftp-root-directory": parameters.get("sftp-root-directory", ""),
                        "sftp-directory": parameters.get("sftp-directory", ""),
                },
                "attributes": {
                    "max-connections": attributes.get("max-connections", ""),
                    "max-connections-per-user": attributes.get("max-connections-per-user", ""),
                    "weight": attributes.get("weight", ""),
                    "failover-only": attributes.get("failover-only", ""),
                    "guacd-port": attributes.get("guacd-port", ""),
                    "guacd-encryption": attributes.get("guacd-encryption", ""),
                    "guacd-hostname": attributes.get("guacd-hostname", ""),
                }
            },
            verify=False,
        )

    def delete_connection(self, identifier: int):
        """Deletes a connection"""

        return requests.delete(
            f"{self.host}/api/session/data/{self.data_source}/connections/{str(identifier)}",
            params=self.params,
            verify=False,
        )

    def list_connection_groups(self):
        """Returns all connection groups"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/connectionGroups",
            params=self.params,
            verify=False,
        ).json(), indent=2)

    def list_connection_group_connections(self):
        """Returns all connection groups connections"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/connectionGroups/ROOT/tree",
            params=self.params,
            verify=False,
        ).json(), indent=2)

    def details_connection_group(self, identifier: str):
        """Returns specific connection group"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/connectionGroups/{identifier}",
            params=self.params,
            verify=False,
        ).json(), indent=2)

    def details_connection_group_connections(self, identifier: str):
        """Returns specific connection group connections"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/connectionGroups/{identifier}/tree",
            params=self.params,
            verify=False,
        ).json(), indent=2)

    def create_connection_group(self, name: str, type: str, parent_identifier: int = None, attributes: dict = {}):
        """Creates a connection group"""

        return requests.post(
            f"{self.host}/api/session/data/{self.data_source}/connectionGroups",
            headers={"Content-Type": "application/json"},
            params=self.params,
            json={
                "parentIdentifier": str(parent_identifier),
                "name": name,
                "type": type,
                "attributes": {
                    "max-connections": attributes.get("max-connections", ""),
                    "max-connections-per-user": attributes.get("max-connections-per-user", ""),
                    "enable-session-affinity": attributes.get("enable-session-affinity", "")
                }
            },
            verify=False,
        )

    def update_connection_group(self, identifier: str, name: str, type: str, parent_identifier: int = None, attributes: dict = {}):
        """
        Updates a connection group
        TODO: IF parent_identifier IS NOT ROOT THEN int IS REQUIRED
        """

        return requests.put(
            f"{self.host}/api/session/data/{self.data_source}/userGroups/{identifier}",
            headers={"Content-Type": "application/json"},
            params=self.params,
            json={
                "parentIdentifier": str(parent_identifier),
                "identifier": identifier,
                "name": name,
                "type": type,
                "attributes": {
                    "max-connections": attributes.get("max-connections", ""),
                    "max-connections-per-user": attributes.get("max-connections-per-user", ""),
                    "enable-session-affinity": attributes.get("enable-session-affinity", "")
                }
            },
            verify=False,
        )

    def delete_connection_group(self, connection_group: str):
        """Deletes a connection group"""

        return requests.delete(
            f"{self.host}/api/session/data/{self.data_source}/connectionGroups/{connection_group}",
            params=self.params,
            verify=False,
        )

    def list_sharing_profile(self):
        """Returns sharing profiles"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/sharingProfiles",
            verify=False,
            params=self.params,
        ).json(), indent=2)

    def details_sharing_profile(self, sharing_id: int):
        """Returns sharing profiles"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/sharingProfiles/{str(sharing_id)}",
            verify=False,
            params=self.params,
        ).json(), indent=2)

    def create_sharing_profile(self, identifier: int, name: str, parameters: dict = {}):
        """Creates connection sharing profile"""

        return requests.post(
            f"{self.host}/api/session/data/{self.data_source}/sharingProfiles",
            headers={"Content-Type": "application/json"},
            verify=False,
            params=self.params,
            json={
                "primaryConnectionIdentifier": str(identifier),
                "name": name,
                "parameters": {
                    "read-only": parameters.get("read-only", "")
                },
                "attributes": {}
            },
        )

    def delete_sharing_profile(self, identifier: int):
        """Deletes connection sharing profile"""

        return requests.delete(
            f"{self.host}/api/session/data/{self.data_source}/sharingProfiles/{str(identifier)}",
            headers={"Content-Type": "application/json"},
            verify=False,
            params=self.params,
        )