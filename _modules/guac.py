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

    def list_users(self):
        """Returns users"""

        return requests.get(
            f"{self.host}/api/session/data/{self.data_source}/users",
            params=self.params,
            verify=False
        ).json()

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
        ).json()

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

    def delete_user(self, username: str):
        """Deletes user"""

        return requests.delete(
            f"{self.host}/api/session/data/{self.data_source}/users/{username}",
            params=self.params,
            verify=False,
        )

    def list_user_groups(self):
        """Returns user groups"""

        return requests.get(
            f"{self.host}/api/session/data/{self.data_source}/userGroups",
            params=self.params,
            verify=False,
        ).json()

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
        ).json()

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

        return requests.get(
            f"{self.host}/api/session/data/{self.data_source}/connections",
            verify=False,
            params=self.params,
        ).json()

    def list_connection_groups(self):
        """Returns connection groups"""

        return requests.get(
            f"{self.host}/api/session/data/{self.data_source}/connectionGroups",
            params=self.params,
            verify=False,
        ).json()

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
        ).json()

    def update_connection_group(self, identifier: str, attributes: dict = {}):
        """Updates a connection group"""

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

    def delete_connection_group(self, connection_group: str):
        """Deletes a connection group"""

        return requests.delete(
            f"{self.host}/api/session/data/{self.data_source}/connectionGroups/{connection_group}",
            params=self.params,
            verify=False,
        )
