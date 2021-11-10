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

def generate_token(host: str, authuser: str, authpass: str):
    return requests.post(
        f"{host}/api/tokens",
        data={"username": authuser, "password": authpass},
        verify=False,
        headers={"Content-Type": "application/x-www-form-urlencoded"}
    ).json()['authToken']

def delete_token(host, token):
    return requests.delete(
        f"{host}/api/tokens/{token}",
        params=token,
        verify=False,
    )

def update_user_password(host, authuser, authpass, username: str, oldpassword: str, newpassword: str):
    token = generate_token(host, authuser, authpass)
    data = requests.put(
        f"{host}/api/session/data/mysql/users/{username}/password",
        headers={"Content-Type": "application/json"},
        params=token,
        json={
            "oldPassword": oldpassword,
            "newPassword": newpassword
        },
        verify=False,
    )
    delete_token(host, token)
    return data