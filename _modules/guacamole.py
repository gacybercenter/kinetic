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

# NOTE(chateaulav): This needs to be flushed out in official guacamole module
#                   and imported from there. do not make changes here seperate
#                   form main project

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

def generate_token(host: str, username: str, password: str):
    return requests.post(
        f"{host}/api/tokens",
        data={"username": username, "password": password},
        verify=False,
        headers={"Content-Type": "application/x-www-form-urlencoded"}
    ).json()['authToken']

def delete_token(host: str, token: str):
    """Deletes a token"""

    return requests.delete(
        f"{host}/api/tokens/{token}",
        params={"token": token},
        verify=False,
    )

def detail_user(host: str,
                data_source: str,
                username: str,
                password: str,
                guac_username: str
                ):
    """Returns users details"""

    token = generate_token(host, data_source, username, password)
    response = json.dumps(requests.get(
        f"{host}/api/session/data/{data_source}/users/{guac_username}",
        params={"token": token},
        verify=False
    ).json(), indent=2)

    delete_token(host, token)
    return response

def update_user(host: str,
                data_source: str,
                username: str,
                password: str,
                guac_username: str,
                attributes: dict = {}
                ):
    """Updates a user"""

    token = generate_token(host, data_source, username, password)
    response = requests.put(
        f"{host}/api/session/data/{data_source}/users/{guac_username}",
        headers={"Content-Type": "application/json"},
        params={"token": token},
        json={
            "username": guac_username,
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

    delete_token(host, token)
    return response

def update_user_password(host: str,
                data_source: str,
                username: str,
                password: str,
                guac_username: str,
                oldpassword: str,
                newpassword: str
                ):
    """Updates a user Password"""

    token = generate_token(host, username, password)
    response = requests.put(
        f"{host}/api/session/data/{data_source}/users/{guac_username}/password",
        headers={"Content-Type": "application/json"},
        params={"token": token},
        json={
            "oldPassword": oldpassword,
            "newPassword": newpassword
        },
        verify=False,
    )

    delete_token(host, token)
    return response