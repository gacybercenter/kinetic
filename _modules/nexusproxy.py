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
## nexusproxy module - primarily used for provisioning repositories
## could potentially be fleshed out and become formal fully-featured
## salt module

import json
import requests
import socket
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

__virtualname__ = "nexusproxy"

def __virtual__():
    return __virtualname__

def list_users(host: str,
               port: str,
               username: str,
               password: str,
               timeout=60
               ):
    '''
    This function is used to list all repositories in Nexus Proxy.
    @param host: Nexus host ip or dns name to inlude the http:// or https://
    @param port: Nexus listening port
    @param username: Nexus username
    @param password: Nexus password
    '''
    response = json.dumps(requests.get(f"{host}:{port}/service/rest/v1/security/users",
                            auth=(username, password),
                            verify=False, timeout=timeout).json(), indent=4)
    return response

def change_user_password(host: str,
                         port: str,
                         username: str,
                         password: str,
                         user: str,
                         new_password: str,
                         timeout=60
                         ):
    '''
    This function is used to change a user's password in Nexus Proxy.
    @param host: Nexus host ip or dns name to inlude the http:// or https://
    @param port: Nexus listening port
    @param username: Nexus username
    @param password: Nexus password
    @param user: User to change password for
    @param new_password: New password for user
    '''
    response = requests.put(f"{host}:{port}/service/rest/v1/security/users/{user}/change-password",
                            auth=(username, password),
                            headers={"Content-Type": "text/plain"},
                            data=new_password,
                            verify=False, timeout=timeout)
    return response.status_code

def list_repositories(host: str,
                      port: str,
                      username: str,
                      password: str,
                      timeout=60
                      ):
    '''
    This function is used to list all repositories in Nexus Proxy.
    @param host: Nexus host ip or dns name to inlude the http:// or https://
    @param port: Nexus listening port
    @param username: Nexus username
    @param password: Nexus password
    '''
    response = json.dumps(requests.get(f"{host}:{port}/service/rest/v1/repositories",
                            auth=(username, password),
                            verify=False, timeout=timeout).json(), indent=4)
    return response

def list_repository(host: str,
                    port: str,
                    username: str,
                    password: str,
                    name: str,
                    timeout=60
                    ):
    '''
    This function is used to list a specific repository in Nexus Proxy.
    @param host: Nexus host ip or dns name to inlude the http:// or https://
    @param port: Nexus listening port
    @param username: Nexus username
    @param password: Nexus password
    @param name: Repository name
    expected return:
    {
      "name" : "debian",
      "format" : "apt",
      "type" : "proxy",
      "url" : "http://10.200.1.173:3142/repository/debian",
      "attributes" : {
        "proxy" : {
          "remoteUrl" : "http://deb.debian.org/debian/"
        }
      }
    }
    '''
    response = requests.get(f"{host}:{port}/service/rest/v1/repositories/{name}",
                            auth=(username, password),
                            verify=False, timeout=timeout)
    if response.status_code == 200:
        response = json.dumps(response.json(), indent=4)
        return response
    return response.status_code

def delete_repository(host: str,
                      port: str,
                      username: str,
                      password: str,
                      name: str,
                      timeout=60
                      ):
    '''
    This function is used to delete a specific repository in Nexus Proxy.
    @param host: Nexus host ip or dns name to inlude the http:// or https://
    @param port: Nexus listening port
    @param username: Nexus username
    @param password: Nexus password
    @param name: Repository name
    '''
    response = json.dumps(requests.delete(f"{host}:{port}/service/rest/v1/repositories/{name}",
                            auth=(username, password),
                            verify=False, timeout=timeout).json(), indent=4)
    return response

def add_proxy_repository(host: str,
                         port: str,
                         username: str,
                         password: str,
                         name: str,
                         repoType: str,
                         remoteUrl: str,
                         timeout=60,
                         **kwargs
                         ):
    '''
    This function is used to add a proxy repository to Nexus Proxy, and currently
    only supports apt, yum, and docker repositories.
    @param host: Nexus host ip or dns name to inlude the http:// or https://
    @param port: Nexus listening port
    @param username: Nexus username
    @param password: Nexus password
    @param name: Repository name
    @param repoType: Repository type
    @param remoteUrl: Remote URL of repository
    @param kwargs: Additional parameters for repository using appropriate dict/list structures
    '''
    payload = {
                "name": name,
                "online": True,
                "storage": {
                    "blobStoreName": "default",
                    "strictContentTypeValidation": True
                    },
                "cleanup": {
                    "policyNames": [
                        "string"
                        ]
                        },
                "proxy": {
                    "remoteUrl": remoteUrl,
                    "contentMaxAge": 1440,
                    "metadataMaxAge": 1440
                    },
                "negativeCache": {
                    "enabled": True,
                    "timeToLive": 1440
                    },
                "httpClient": {
                    "blocked": False,
                    "autoBlock": True,
                    "connection": {
                        "retries": 0,
                        "userAgentSuffix": "string",
                        "timeout": 60,
                        "enableCircularRedirects": False,
                        "enableCookies": False,
                        "useTrustStore": False
                        },
                    "authentication": {
                        "type": "username",
                        "username": "string",
                        "password": "string",
                        "ntlmHost": "string",
                        "ntlmDomain": "string"
                        }
                    },
                "routingRule": "string",
                "replication": {
                    "preemptivePullEnabled": False,
                    "assetPathRegex": "string"
                    }
                }
    if repoType == "apt":
        payload.update({
                    "apt": {
                        "distribution": "*",
                        "flat": False
                        }
                    })
    elif repoType == "yum":
        payload.update({
            "yumSigning": {
                "keypair": "string",
                "passphrase": "string"
                }
            })
    elif repoType == "docker":
        payload.update({
            "docker": { 
                "v1Enabled": False,
                "forceBasicAuth": True,
                "httpPort": 8082,
                "httpsPort": 8083,
                "subdomain": "docker-a"
                },
            "dockerProxy": {
                "indexType": "HUB",
                "indexUrl": "string",
                "cacheForeignLayers": True,
                "foreignLayerUrlWhitelist": [
                    "string"
                    ]
                }
            })
    payload.update(kwargs)
    response = requests.post(f"{host}:{port}/service/rest/v1/repositories/{repoType}/proxy",
                            auth=(username, password),
                            headers={"Content-Type": "application/json"},
                            json=payload,
                            verify=False, timeout=timeout)
    return response.status_code
