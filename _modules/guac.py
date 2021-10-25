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

from salt.modules.guacamole import Session

__virtualname__ = "guac"

def __virtual__():
    return __virtualname__

def update_password(host, authuser, authpass, username, oldpassword, newpassword):
    s = Session(host, authuser, authpass)
    data = s.update_user_password(username, oldpassword, newpassword)
    s.delete_token()
    return data

def create_group(host, authuser, authpass, identifier, attributes):
    s = Session(host, authuser, authpass)
    data = s.create_user_group(identifier, attributes)
    s.delete_token()
    return data

def update_permissions(host, authuser, authpass, username, operation, cuser, cusergroup, cconnect, cconnectgroup, cshare, admin):
    s = Session(host, authuser, authpass)
    data = s.update_user_permissions(username, operation, cuser, cusergroup, cconnect, cconnectgroup, cshare, admin)
    s.delete_token()
    return data