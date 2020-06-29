## danos module - helper functions for danos state module
## could potentially be fleshed out and become formal fully-featured
## salt module
import requests, urllib3, base64, json

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

__virtualname__ = 'danos'

def __virtual__():
    return __virtualname__

def make_auth_token(username, password):
    return base64.b64encode((username+':'+password).encode('utf-8'))

def make_session(host, username, password):
    auth_token = make_auth_token(username, password)
    url = "https://"+host+"/rest/conf"
    headers = {'Authorization': 'Basic '+auth_token.decode('utf-8')}
    session = requests.post(url, headers=headers, verify=False)
    return session.headers.get('location')

def delete_session(host, username, password, location):
    auth_token = make_auth_token(username, password)
    url = "https://"+host+"/"+location
    headers = {'Authorization': 'Basic '+auth_token.decode('utf-8')}
    delete_session = requests.delete(url, headers=headers, verify=False)
    return delete_session.text

def get_full_configuration(host, username, password, **kwargs):
    ret = {"result": None, "comment": ""}
    auth_token = make_auth_token(username, password)
    location = make_session(host, username, password)
    url = "https://"+host+"/"+location+"/show"
    headers = {'Authorization': 'Basic '+auth_token.decode('utf-8')}
    configuration = requests.post(url, headers=headers, verify=False)
    delete_session(host, username, password, location)
    ret["result"] = True
    ret["comment"] = configuration.text
    return ret

def get_configuration(host, username, password, path, **kwargs):
    auth_token = make_auth_token(username, password)
    location = make_session(host, username, password)
    url = "https://"+host+"/"+location+path
    headers = {'Authorization': 'Basic '+auth_token.decode('utf-8')}
    configuration = requests.get(url, headers=headers, verify=False)
    delete_session(host, username, password, location)
    return configuration.text

def delete_configuration(host, username, password, path, location=None, **kwargs):
    standalone = False
    auth_token = make_auth_token(username, password)
    if location is None:
        standalone = True
        location = make_session(host, username, password)
    delete_url = "https://"+host+"/"+location+"/delete"+path
    headers = {'Authorization': 'Basic '+auth_token.decode('utf-8')}
    delete = requests.put(delete_url, headers=headers, verify=False)
    if standalone == True:
        commit = commit_configuration(host, username, password, location)
        delete_session(host, username, password, location)
    return delete.text

### This function doesn't do anything and errors out.
### See https://danosproject.atlassian.net/jira/servicedesk/projects/DAN/issues/DAN-125
def compare_configuration(host, username, password, location, **kwargs):
    auth_token = make_auth_token(username, password)
    url = "https://"+host+"/"+location+"/compare"
    headers = {'Authorization': 'Basic '+auth_token.decode('utf-8')}
    compare = requests.post(url, headers=headers, verify=False)
    return compare.text

def commit_configuration(host, username, password, location, **kwargs):
    auth_token = make_auth_token(username, password)
    url = "https://"+host+"/"+location+"/commit"
    headers = {'Authorization': 'Basic '+auth_token.decode('utf-8')}
    commit = requests.post(url, headers=headers, verify=False)
    return commit.text

def set_configuration(host, username, password, path, location=None, **kwargs):
    standalone = False
    auth_token = make_auth_token(username, password)
    if location is None:
        standalone = True
        location = make_session(host, username, password)
    url = "https://"+host+"/"+location+"/set"+path
    headers = {'Authorization': 'Basic '+auth_token.decode('utf-8')}
    set = requests.put(url, headers=headers, verify=False)
#   The below function call doesn't do anything because compare isn't implemented
#   in the REST API.  See https://danosproject.atlassian.net/jira/servicedesk/projects/DAN/issues/DAN-125
#    compare = compare_configuration(host, username, password, location)
    if standalone == True:
        commit = commit_configuration(host, username, password, location)
        delete_session(host, username, password, location)
    return set.text
