#!/usr/bin/env python3

import importlib

exists = importlib.util.find_spec("pyghmi") is not None
if exists:
    from pyghmi.ipmi.command import Command

    def ipmi_config():
        grains = {}
        ipmi = {}
        try:
            command = Command()
        except FileNotFoundError:
            return

        config = command.get_net_configuration()
        ipmi["ipv4_address"] = config["ipv4_address"]
        ipmi["mac_address"] = config["mac_address"]
        grains["ipmi"] = ipmi

        return grains


if __name__ == "__main__":
    if exists:
        print(ipmi_config())
