## work with metal inventory based on data pulled from pillar
import ipaddress, socket, requests, urllib3, re, json

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
socket.setdefaulttimeout(0.1)

__virtualname__ = 'metal'

def __virtual__():
    return __virtualname__

def tcp_connect(ip, port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex((str(ip), port))
    sock.close()
    return result

def gather(network):
    redfish_endpoints = {}
    for ip in ipaddress.IPv4Network(network):
        if tcp_connect(ip, 443) == 0:
            redfish_status = requests.get('https://'+str(ip)+'/redfish/v1', timeout=0.5, verify=False)
            if re.match('^.*("RedfishVersion":"1.0.1").*$', redfish_status.text) != None:
                body = json.loads(redfish_status.text)
                redfish_endpoints[body['UUID']] = str(ip)
    return redfish_endpoints
