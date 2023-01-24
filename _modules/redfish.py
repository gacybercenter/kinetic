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

## redfish module - primarily used for bootstrapping
## could potentially be fleshed out and become formal fully-featured
## salt module

import ipaddress
import json
import pyghmi.ipmi.command
import redfish
import requests
import socket
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
socket.setdefaulttimeout(0.5)

__virtualname__ = "redfish"


def __virtual__():
    return __virtualname__


def tcp_connect(ip_address, port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex((str(ip_address), port))
    sock.close()
    return result


def check_version(ip_address):
    redfish_version = requests.get(
        "https://" + str(ip_address) + "/redfish/v1", timeout=1, verify=False
    )
    ### This will work for now, needs better logic to handle all supported versions
    response = redfish_version.json()
    version = response["RedfishVersion"]
    version_subs = version.split('.')
    version_subs = [int(sub) for sub in version_subs]

    if bool(version_subs[0] >= 1 and version_subs[1] >= 0):
        return True
    return False


def login(host, username, password):
    session = redfish.redfish_client(
        base_url="https://" + host,
        username=username,
        password=password,
        default_prefix="/redfish/v1",
    )
    session.login(auth="session")
    return session


def gather_endpoints(network, username, password):
    redfish_endpoints = {}
    for ip_address in ipaddress.IPv4Network(network):
        if tcp_connect(ip_address, 443) == 0:
            try:
                #if check_version(ip) == True:
                session = login(str(ip_address), username, password)
                redfish_status = session.get("/redfish/v1/Systems/1", None)
                body = json.loads(redfish_status.text)
                redfish_endpoints[body["UUID"]] = str(ip_address)
                session.logout()
            except:
                print(f"Error processing {ip_address}")
                pass
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
    return json.loads(response.text)["UUID"]


def set_bootonce(host, username, password, mode, target):
    ### Default method is to use redfish api
    ### if statuscode != 200, fallback to raw ipmi
    session = login(host, username, password)
    response = session.patch(
        "/redfish/v1/Systems/1/",
        body={
            "Boot": {
                "BootSourceOverrideMode": mode,
                "BootSourceOverrideTarget": target,
                "BootSourceOverrideEnabled": "Once",
            }
        },
    )
    try:
        session.logout()
    except:
        print("Redfish logout failed. This is probably a bug in your particular redfish implementation and can likely be ignored.")
    if response.status != 200:
        cmd = pyghmi.ipmi.command.Command(
            bmc=host, userid=username, password=password, keepalive=False
        )
        cmd.set_bootdev(bootdev="network", uefiboot=True)
        return cmd.get_bootdev()
    return response.text


def reset_host(host, username, password):
    session = login(host, username, password)
    status = session.get("/redfish/v1/Systems/1", None)
    if json.loads(status.text)["PowerState"] == "On":
        response = session.post(
            "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset/",
            body={"ResetType": "ForceRestart"},
        )
    if json.loads(status.text)["PowerState"] == "Off":
        response = session.post(
            "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset/",
            body={"ResetType": "On"},
        )
    session.logout()
    return response.text
