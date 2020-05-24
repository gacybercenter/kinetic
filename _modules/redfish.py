## work with metal inventory based on data pulled from pillar
import redfish, json

__virtualname__ = 'redfish'

def __virtual__():
    return __virtualname__

def login(host, username, password):
    session = redfish.redfish_client(base_url="https://"+host, \
                                     username=username, \
                                     password=password, \
                                     default_prefix="/redfish/v1")
    session.login(auth="session")
    return session

def get_system(host, username, password):
    session = login(host, username, password)
    response = session.get("/redfish/v1/Systems/1/", None)
    session.logout()
    return response.text

def get_uuid(host, username, password):
    session = login(host, username, password)
    response = session.get("/redfish/v1/Systems/1/", None)
    session.logout()
    return json.loads(response.text)['UUID']
