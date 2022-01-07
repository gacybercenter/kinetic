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

## danos module - helper functions for danos state module
## could potentially be fleshed out and become formal fully-featured
## salt module
import requests, urllib3, base64

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

__virtualname__ = 'danos'

def __virtual__():
    return __virtualname__

def make_auth_header(username, password):
    token = base64.b64encode((username+':'+password).encode('utf-8'))
    headers = {'Authorization': 'Basic '+token.decode('utf-8')}
    return headers

def make_session(host, username, password):
    headers = make_auth_header(username, password)
    url = "https://"+host+"/rest/conf"
    session = requests.post(url, headers=headers, verify=False)
    return session.headers.get('location')

def delete_session(host, username, password, location):
    headers = make_auth_header(username, password)
    url = "https://"+host+"/"+location
    delete_session = requests.delete(url, headers=headers, verify=False)
    return delete_session.text

def reset_dns_forwarding_cache(host, username, password, **kwargs):
    headers = make_auth_header(username, password)
    url = "https://"+host+"/rest/op/reset/dns/forwarding/cache"
    command = requests.post(url, headers=headers, verify=False)
    return command.text

def get_full_configuration(host, username, password, **kwargs):
    headers = make_auth_header(username, password)
    location = make_session(host, username, password)
    url = "https://"+host+"/"+location+"/show"
    configuration = requests.post(url, headers=headers, verify=False)
    delete_session(host, username, password, location)
    return configuration.text

def get_configuration(host, username, password, path, **kwargs):
    headers = make_auth_header(username, password)
    location = make_session(host, username, password)
    url = "https://"+host+"/"+location+path
    get = requests.get(url, headers=headers, verify=False)
    delete_session(host, username, password, location)
    return get.text

def delete_configuration(host, username, password, path, location=None, **kwargs):
    standalone = False
    headers = make_auth_header(username, password)
    if location is None:
        standalone = True
        location = make_session(host, username, password)
    url = "https://"+host+"/"+location+"/delete"+path
    delete = requests.put(url, headers=headers, verify=False)
    if standalone == True:
        commit = commit_configuration(host, username, password, location)
        delete_session(host, username, password, location)
    return delete.text

### This function doesn't do anything and errors out.
### See https://danosproject.atlassian.net/jira/servicedesk/projects/DAN/issues/DAN-125
def compare_configuration(host, username, password, location, **kwargs):
    headers = make_auth_header(username, password)
    url = "https://"+host+"/"+location+"/compare"
    compare = requests.post(url, headers=headers, verify=False)
    return compare.text

def commit_configuration(host, username, password, location, **kwargs):
    headers = make_auth_header(username, password)
    url = "https://"+host+"/"+location+"/commit"
    commit = requests.post(url, headers=headers, verify=False)
    return commit.text

def set_configuration(host, username, password, path, location=None, **kwargs):
    standalone = False
    headers = make_auth_header(username, password)
    if location is None:
        standalone = True
        location = make_session(host, username, password)
    url = "https://"+host+"/"+location+"/set"+path
    set = requests.put(url, headers=headers, verify=False)
#   The below function call doesn't do anything because compare isn't implemented
#   in the REST API.  See https://danosproject.atlassian.net/jira/servicedesk/projects/DAN/issues/DAN-125
#    compare = compare_configuration(host, username, password, location)
    if standalone == True:
        commit = commit_configuration(host, username, password, location)
        delete_session(host, username, password, location)
    return set.text
