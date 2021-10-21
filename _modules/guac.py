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

__virtualname__ = "guac"

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

    def list_users(self):
        """Returns users"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/users",
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
                    "valid-from": attributes.get("valid-from", ""),
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

    def update_user_connection(self, username: str, connectionid: str, operation: str = "add", isgroup: bool = False):
        """Change a user Connections"""

        if not isgroup:
            path =  f"/connectionPermissions/{connectionid}"
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

    def delete_user(self, username: str):
        """Deletes user"""

        return requests.delete(
            f"{self.host}/api/session/data/{self.data_source}/users/{username}",
            params=self.params,
            verify=False,
        )

    def list_user_groups(self):
        """Returns user groups"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/userGroups",
            params=self.params,
            verify=False,
        ).json(), indent=2)

    def create_user_group(self, identifier: str, attributes: dict = {}):
        """Creates a user group"""

        return requests.post(
            f"{self.host}/api/session/data/{self.data_source}/userGroups",
            headers={"Content-Type": "application/json"},
            params=self.params,
            json={
                "identifier": identifier,
                "attributes": {
                    "disabled": attributes.get("disabled", "")
                }
            },
            verify=False,
        )

    def update_user_group(self, identifier: str, attributes: dict = {}):
        """Updates a user group"""
        
        return requests.put(
            f"{self.host}/api/session/data/{self.data_source}/userGroups/{identifier}",
            headers={"Content-Type": "application/json"},
            params=self.params,
            json={
                "identifier": identifier,
                "attributes": {
                    "disabled": attributes.get("disabled", "")
                }
            },
            verify=False,
        )

    def delete_user_group(self, user_group: str):
        """Deletes a user group"""

        return requests.delete(
            f"{self.host}/api/session/data/{self.data_source}/userGroups/{user_group}",
            params=self.params,
            verify=False,
        )

    def list_connections(self):
        """Returns connections"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/connections",
            verify=False,
            params=self.params,
        ).json(), indent=2)

    def create_ssh_connection(self, name: str, parent_identifier: str, parameters: dict = {}, attributes: dict = {}):
        """Creates an SSH connection
        parent_identifier is required if placing in a specific connection group
        parameters = {"hostname": "", "port": "", "username": "", "password": ""}
        attributes = {"max-connections": "", "max-connections-per-user": "" }
        """

        return requests.post(
            f"{self.host}/api/session/data/{self.data_source}/connections",
            headers={"Content-Type": "application/json"},
            params=self.params,
            json={
                "parentIdentifier": parent_identifier,
                "name": name,
                "protocol": "ssh",
                "parameters": {
                    "port": parameters.get("port", ""),
                    "read-only": parameters.get("read-only", ""),
                    "swap-red-blue": parameters.get("swap-red-blue", ""),
                    "cursor": parameters.get("cursor", ""),
                    "color-depth": parameters.get("color-depth", ""),
                    "clipboard-encoding": parameters.get("clipboard-encoding", ""),
                    "disable-copy": parameters.get("disable-copy", ""),
                    "disable-paste": parameters.get("disable-paste", ""),
                    "dest-port": parameters.get("dest-port", ""),
                    "recording-exclude-output": parameters.get("recording-exclude-output", ""),
                    "recording-exclude-mouse": parameters.get("recording-exclude-mouse", ""),
                    "recording-include-keys": parameters.get("recording-include-keys", ""),
                    "create-recording-path": parameters.get("create-recording-path", ""),
                    "enable-sftp": parameters.get("enable-sftp", ""),
                    "sftp-port": parameters.get("sftp-port", ""),
                    "sftp-server-alive-interval": parameters.get("sftp-server-alive-interval", ""),
                    "enable-audio": parameters.get("enable-audio", ""),
                    "color-scheme": parameters.get("color-scheme", ""),
                    "font-size": parameters.get("font-size", ""),
                    "scrollback": parameters.get("scrollback", ""),
                    "timezone": parameters.get("timezone", None),
                    "server-alive-interval": parameters.get("server-alive-interval", ""),
                    "backspace": parameters.get("backspace", ""),
                    "terminal-type": parameters.get("terminal-type", ""),
                    "create-typescript-path": parameters.get("create-typescript-path", ""),
                    "hostname": parameters.get("hostname", ""),
                    "host-key": parameters.get("host-key", ""),
                    "private-key": parameters.get("private-key", ""),
                    "username": parameters.get("username", ""),
                    "password": parameters.get("password", ""),
                    "passphrase": parameters.get("passphrase", ""),
                    "font-name": parameters.get("font-name", ""),
                    "command": parameters.get("command", ""),
                    "locale": parameters.get("locale", ""),
                    "typescript-path": parameters.get("typescript-path", ""),
                    "typescript-name": parameters.get("typescript-name", ""),
                    "recording-path": parameters.get("recording-path", ""),
                    "recording-name": parameters.get("recording-name", ""),
                    "sftp-root-directory": parameters.get("sftp-root-directory", "")
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
                        "gateway-hostname": parameters.get("gateway-hostname", ""),
                        "gateway-username": parameters.get("gateway-username", ""),
                        "gateway-password": parameters.get("gateway-password", ""),
                        "gateway-domain": parameters.get("gateway-domain", ""),
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

    def delete_connection(self, identifier: str):
        """Deletes a connection"""

        return requests.delete(
            f"{self.host}/api/session/data/{self.data_source}/connections/{identifier}",
            params=self.params,
            verify=False,
        )

    def list_connection_groups(self):
        """Returns connection groups"""

        return json.dumps(requests.get(
            f"{self.host}/api/session/data/{self.data_source}/connectionGroups",
            params=self.params,
            verify=False,
        ).json(), indent=2)

    def create_connection_group(self, name: str, type: str, parent_identifier: str = None, attributes: dict = {}):
        """Creates a connection group"""

        return requests.post(
            f"{self.host}/api/session/data/{self.data_source}/connectionGroups",
            headers={"Content-Type": "application/json"},
            params=self.params,
            json={
                "parentIdentifier": parent_identifier,
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

    def update_connection_group(self, identifier: str, name: str, type: str, parent_identifier: str = None, attributes: dict = {}):
        """Updates a connection group"""

        return requests.put(
            f"{self.host}/api/session/data/{self.data_source}/userGroups/{identifier}",
            headers={"Content-Type": "application/json"},
            params=self.params,
            json={
                "parentIdentifier": parent_identifier,
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

    def create_sharing_profile(self, identifier: str, name: str, parameters: dict = {}):
        """Creates connection sharing profile"""

        return requests.post(
            f"{self.host}/api/session/data/{self.data_source}/sharingProfiles",
            headers={"Content-Type": "application/json"},
            verify=False,
            params=self.params,
            json={
                "primaryConnectionIdentifier": identifier,
                "name": name,
                "parameters": {
                    "read-only": parameters.get("read-only", "")
                },
                "attributes": {}
            },
        )

    def delete_sharing_profile(self, identifier: str):
        """Deletes connection sharing profile"""

        return requests.delete(
            f"{self.host}/api/session/data/{self.data_source}/sharingProfiles/{identifier}",
            headers={"Content-Type": "application/json"},
            verify=False,
            params=self.params,
        )