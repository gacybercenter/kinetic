#!/usr/bin/python3

import redfish

host_session = redfish.redfish_client(base_url="{{ url }}", \
                                     username="{{ username }}", \
                                     password="{{ password }}", \
                                     default_prefix="/redfish/v1")

host_session.login(auth="session")

system = host_session.get("redfish/v1/Systems/1", None)
chassis = host_session.get("redfish/v1/Chassis/1", None)

print (system.text)
