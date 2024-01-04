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
import socket
import urllib3
import re

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
socket.setdefaulttimeout(0.5)

__virtualname__ = "redfish"


def __virtual__():
    return __virtualname__


def tcp_connect(host, port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex((str(host), port))
    sock.close()
    return result


def check_type(session):
    try:
        redfish_status = session.get("/redfish/v1/Systems", None)
        body = json.loads(redfish_status.text)
        matching = (body["Members"])
        system = re.search(r'/Systems/(.+)', matching[0]['@odata.id']).group(1)
        if system == "1":
            type = "BMC"
            return type
        elif system == "system":
            type = "OpenBMC"
            return type
    except:
        print(f"Could not determine the system type.")


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
    for host in ipaddress.IPv4Network(network):
        if tcp_connect(host, 443) == 0:
            try:
                session = login(str(host), username, password)
                if check_type(session) == "BMC":
                    redfish_status = session.get("/redfish/v1/Systems/1", None)
                    body = json.loads(redfish_status.text)
                    redfish_endpoints[body["UUID"]] = str(host)
                    session.logout()
                elif check_type(session) == "OpenBMC":
                    redfish_status = session.get("/redfish/v1/Systems/system", None)
                    body = json.loads(redfish_status.text)
                    redfish_endpoints[body["UUID"]] = str(host)
                    session.logout()
                else:
                    session.logout()
            except:
                print(f"Error processing {host}")
                pass
    return redfish_endpoints


def get_system(host, username, password, redfish_target='Systems', redfish_path=None):
    """
    Consolidates the ability to query 'Systems', 'Managers', and 'Chassis' resources
    within a single function. Defaults to a basic GET of the '/redfish/v1/Systems/1/' path.

    :param redfish_target: This allows to specify 'Systems', 'Managers', Chassis'
    within the '/redfish/v1/{redfish_target}/1/' path.
    :param redfish_path: This alllows to specify a path beyond the '/redfish/v1/Systems/1/' path.
    """
    redfish_targets = ['Systems', 'Managers', 'Chassis']
    if redfish_target not in redfish_targets:
        raise ValueError("Invalid redfish target. Expected one of: %s" % redfish_target)
    try:
        session = login(host, username, password)
        if check_type(session) == "BMC":
            if redfish_path is None:
                response = session.get(f'/redfish/v1/{redfish_target}/1/', None)
            else:
                response = session.get(f'/redfish/v1/{redfish_target}/1/{redfish_path}', None)
            session.logout()
            dump = json.loads(response.text)
            print(json.dumps(dump, indent=4))
            return 
        elif check_type(session) == "OpenBMC":
            if redfish_path is None:
                response = session.get(f'/redfish/v1/{redfish_target}/system/', None)
            else:
                response = session.get(f'/redfish/v1/{redfish_target}/system/{redfish_path}', None)
            session.logout()
            dump = json.loads(response.text)
            print(json.dumps(dump, indent=4))
            return
        else:
            session.logout() 
    except:
        print("Redfish get_system failed.")


def get_uuid(host, username, password):
    try:
        session = login(str(host), username, password)
        if check_type(session) == "BMC":
            response = session.get("/redfish/v1/Systems/1/", None)
            session.logout()
            return json.loads(response.text)["UUID"]
        elif check_type(session) == "OpenBMC":
            response = session.get("/redfish/v1/Systems/system/", None)
            session.logout()
            return json.loads(response.text)["UUID"]
        else:
            session.logout()
    except:
        print("Redfish get_uuid failed.")


def get_bootonce(host, username, password):
    try:
        session = login(str(host), username, password)
        if check_type(session) == "BMC":
            response = session.get("/redfish/v1/Systems/1/", None)
            session.logout()
            return json.loads(response.text)["Boot"]["BootSourceOverrideTarget"]
        elif check_type(session) == "OpenBMC":
            response = session.get("/redfish/v1/Systems/system/", None)
            session.logout()
            return json.loads(response.text)["Boot"]["BootSourceOverrideTarget"]
        else:
            session.logout()
    except:
        print("Redfish get_bootonce failed.")


def set_bootonce(host, username, password, mode, target):
    ### Default method is to use redfish api
    ### if statuscode != 200, fallback to raw ipmi
    try:
        session = login(str(host), username, password)
        if check_type(session) == "BMC":
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
        elif check_type(session) == "OpenBMC":
            response = session.patch(
                "/redfish/v1/Systems/system/",
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
                pxe = get_bootonce(host, username, password)
                if pxe == 'Pxe' or pxe == 'PXE':
                    status = '200'
                    return status
                else:
                    return response.status
            else:
                return response.text
        else:
            session.logout()
    except:
        print("Redfish set_bootonce failed.")


# TODO(chateaulav): retry mechanism for physical provisioning, need to
# identify correct variables to use. will leverage .sls to perform retries
def set_bootonce_retry(host, username, password, mode, target):
    try:
        session = login(str(host), username, password)
        if check_type(session) == "BMC":
            status = session.get("/redfish/v1/Systems/1", None)
            if json.loads(status.text)["PowerState"] == "On":
                if json.loads(status.text)["Boot"]["BootSourceOverrideTarget"] == "PXE":
                    set_bootonce(host, username, password, mode, target)
                    reset_host(host, username, password)
        elif check_type(session) == "OpenBMC":
            status = session.get("/redfish/v1/Systems/system", None)
            if json.loads(status.text)["PowerState"] == "On":
                if json.loads(status.text)["Boot"]["BootSourceOverrideTarget"] == "PXE":
                    set_bootonce(host, username, password, mode, target)
                    reset_host(host, username, password)
        else:
            session.logout()
    except:
        print("Redfish set_bootonce_retry failed.")


# TODO(brecaldwell): try to get more verbose output. Right now it doesn't say anything for OpenBMC as type
def reset_host(host, username, password):
    try:
        session = login(str(host), username, password)
        if check_type(session) == "BMC":
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
        elif check_type(session) == "OpenBMC":
            status = session.get("/redfish/v1/Systems/system", None)
            if json.loads(status.text)["PowerState"] == "On":
                response = session.post(
                    "/redfish/v1/Systems/system/Actions/ComputerSystem.Reset/",
                    body={"ResetType": "ForceRestart"},
                )
            if json.loads(status.text)["PowerState"] == "Off":
                response = session.post(
                    "/redfish/v1/Systems/system/Actions/ComputerSystem.Reset/",
                    body={"ResetType": "On"},
                )
            session.logout()
        else:
            session.logout()
    except:
        print("Redfish reset_host failed.")
