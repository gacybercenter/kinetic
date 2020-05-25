## redfish module - primarily used for bootstrapping
## could potentially be fleshed out and become formal fully-featured
## salt module
import redfish, json, ipaddress, socket, requests, urllib3, re

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
socket.setdefaulttimeout(0.1)

__virtualname__ = 'redfish'

def __virtual__():
    return __virtualname__

def tcp_connect(ip, port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex((str(ip), port))
    sock.close()
    return result

def check_version(ip):
    redfish_version = requests.get('https://'+str(ip)+'/redfish/v1', timeout=0.5, verify=False)
    if re.match('^.*("RedfishVersion":"1.0.1").*$', redfish_version.text) != None:
        return True
    else:
        return False

def login(host, username, password):
    session = redfish.redfish_client(base_url="https://"+host, \
                                     username=username, \
                                     password=password, \
                                     default_prefix="/redfish/v1")
    session.login(auth="session")
    return session

def gather_endpoints(network, username, password):
    redfish_endpoints = {}
    for ip in ipaddress.IPv4Network(network):
        if tcp_connect(ip, 443) == 0:
            if check_version(ip) == True:
                session = login(str(ip), username, password)
                redfish_status = session.get('/redfish/v1/Systems/1', None)
                body = json.loads(redfish_status.text)
                redfish_endpoints[body['UUID']] = str(ip)
                session.logout()
    return redfish_endpoints

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

def set_bootonce(host, username, password, mode, target):
    session = login(host, username, password)
    response = session.patch("/redfish/v1/Systems/1/", \
                             body={"Boot":{
                                     "BootSourceOverrideMode" : mode,
                                     "BootSourceOverrideTarget" : target,
                                     "BootSourceOverrideEnabled" : "Once"
                                    }
                                  })
    session.logout()
    return response.text

def reset_host(host, username, password):
    session = login(host, username, password)
    status = session.get("/redfish/v1/Systems/1", None)
    if json.loads(status.text)['PowerState'] == "On":
      response = session.post("/redfish/v1/Systems/1/Actions/ComputerSystem.Reset/", \
                              body={"ResetType":"ForceRestart"})
    if json.loads(status.text)['PowerState'] == "Off":
      response = session.post("/redfish/v1/Systems/1/Actions/ComputerSystem.Reset/", \
                              body={"ResetType":"On"})
    session.logout()
    return response.text
