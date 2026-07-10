# -*- coding: utf-8 -*-
"""
SaltStack execution module for managing Netplan configurations.

This module provides functions to generate and apply Netplan configurations
with support for bonds, bridges, and different host types (controller vs others).
"""

import json
import os
import tempfile

import salt.utils.files
from salt.exceptions import CommandExecutionError

__virtualname__ = "kinetic_netplan"


def __virtual__():
    """
    Only load if netplan is available.
    """
    if os.path.exists("/usr/sbin/netplan"):
        return __virtualname__
    return (False, "Netplan is not available on this system.")


def generate_config(pillar_data=None, host_type=None):
    """
    Generate Netplan configuration based on pillar data.

    Args:
        pillar_data (dict): Pillar data to use. If None, uses __salt__['pillar.get']()
        host_type (str): Host type (e.g. 'controller'). If None, uses grains['type']

    Returns:
        dict: Configuration with 'success', 'config', and 'message'
    """
    try:
        if not pillar_data:
            pillar_data = __salt__["pillar.get"]("hosts", {})

        if not host_type:
            host_type = __salt__["grains.get"]("type", "default")

        config = {
            "network": {
                "version": 2,
                "renderer": "networkd",
                "ethernets": {},
                "bonds": {},
                "bridges": {},
            }
        }

        networks = pillar_data.get(host_type, {}).get("networks", {})

        # Get DHCP options and networking addresses from top-level pillar
        dhcp_options = __salt__["pillar.get"]("dhcp-options", {})
        networking_addresses = __salt__["pillar.get"]("networking:addresses", {})

        for network_name, network_config in networks.items():
            if not network_config.get("managed", True):
                continue

            interfaces = network_config.get("interfaces", [])
            subnet_cidr = __salt__["pillar.get"]("networking:subnets", {}).get(
                network_name, "192.168.1.0/24"
            )
            cidr_prefix = subnet_cidr.split("/")[1]

            # Get management IP for this host
            management_ip = (
                __salt__["pillar.get"]("bmh", {})
                .get(__salt__["grains.get"]("id", ""), {})
                .get("network", {})
                .get("management_ip", "192.168.1.100")
            )

            if len(interfaces) > 1:
                # Ensure each physical interface is declared in ethernets
                for iface in interfaces:
                    if iface not in config["network"]["ethernets"]:
                        config["network"]["ethernets"][iface] = {
                            "dhcp4": False,
                            "mtu": 9000,
                        }

                # Create bond
                bond_name = f"bond-{network_name}"
                config["network"]["bonds"][bond_name] = {
                    "interfaces": interfaces,
                    "parameters": {
                        "mode": "802.3ad",
                        "mii-monitor-interval": 100,
                        "lacp-rate": "fast",
                    },
                    "mtu": 9000,
                    "dhcp4": False,
                }

                interface_ref = bond_name
            else:
                interface_ref = interfaces[0]
                if interface_ref not in config["network"]["ethernets"]:
                    config["network"]["ethernets"][interface_ref] = {
                        "dhcp4": False,
                        "mtu": 9000,
                    }

            if network_name == "management":
                if host_type == "controller":
                    # Management uses bridge on controllers
                    config["network"]["bridges"]["management_br"] = {
                        "interfaces": [interface_ref],
                        "addresses": [f"{management_ip}/{cidr_prefix}"],
                        "routes": [
                            {
                                "to": "default",
                                "via": dhcp_options.get("mgmt_gateway", "192.168.1.1"),
                            }
                        ],
                        "nameservers": {
                            "addresses": [dhcp_options.get("dns", "8.8.8.8")]
                        },
                        "parameters": {"stp": False, "forward-delay": 0},
                    }
                else:
                    # Non-controller management uses direct interface
                    if interface_ref not in config["network"]["ethernets"]:
                        config["network"]["ethernets"][interface_ref] = {}
                    config["network"]["ethernets"][interface_ref].update(
                        {
                            "addresses": [f"{management_ip}/{cidr_prefix}"],
                            "routes": [
                                {
                                    "to": "default",
                                    "via": dhcp_options.get(
                                        "mgmt_gateway", "192.168.1.1"
                                    ),
                                }
                            ],
                            "nameservers": {
                                "addresses": [dhcp_options.get("dns", "8.8.8.8")]
                            },
                        }
                    )
            else:
                # Non-management networks use bridges with no IP
                bridge_name = f"{network_name}_br"
                config["network"]["bridges"][bridge_name] = {
                    "interfaces": [interface_ref],
                    "dhcp4": False,
                    "parameters": {"stp": False, "forward-delay": 0},
                }

        return {
            "success": True,
            "config": config,
            "message": "Netplan configuration generated successfully",
        }

    except Exception as e:
        return {
            "success": False,
            "config": {},
            "message": f"Failed to generate Netplan configuration: {str(e)}",
        }


def apply_config(config=None, pillar_key="hosts"):
    """
    Apply Netplan configuration.

    Args:
        config (dict): Netplan config to apply. If None, generated from pillar.
        pillar_key (str): Pillar key to use for config generation. Defaults to 'hosts'.

    Returns:
        dict: Result with success, changes, and message.
    """
    try:
        if not config:
            config_result = generate_config()
            if not config_result["success"]:
                return config_result
            config = config_result["config"]

        # Write configuration directly to target file
        import yaml

        with open("/etc/netplan/01-netcfg.yaml", "w") as f:
            yaml.safe_dump(config, f, default_flow_style=False, sort_keys=False)

        os.chown("/etc/netplan/01-netcfg.yaml", 0, 0)
        os.chmod("/etc/netplan/01-netcfg.yaml", 0o600)

        # Apply configuration
        result = __salt__["cmd.run_all"]("netplan apply", python_shell=False)

        if result["retcode"] == 0:
            return {
                "success": True,
                "changes": {"netplan": "applied"},
                "message": "Netplan configuration applied successfully",
            }
        else:
            return {
                "success": False,
                "changes": {},
                "message": f"Netplan apply failed: {result.get('stderr', result.get('stdout', 'Unknown error'))}",
            }

    except Exception as e:
        return {
            "success": False,
            "changes": {},
            "message": f"Failed to apply Netplan configuration: {str(e)}",
        }


def promisc_mode(networks=None):
    """
    Create and enable a systemd one-shot service to persistently
    enable promiscuous mode on the physical interfaces of
    non-management networks.
    """
    try:
        if not networks:
            pillar_data = __salt__["pillar.get"]("hosts", {})
            host_type = __salt__["grains.get"]("type", "default")
            networks = []
            for network, cfg in (
                pillar_data.get(host_type, {}).get("networks", {}).items()
            ):
                if network != "management" and cfg.get("managed", True):
                    networks.append(network)

        if not networks:
            return {"success": True, "message": "No networks require promiscuous mode"}

        # Collect all physical interfaces
        interfaces = set()
        for network in networks:
            ifaces = __salt__["pillar.get"](
                f"hosts:{host_type}:networks:{network}:interfaces", []
            )
            interfaces.update(ifaces)

        if not interfaces:
            return {
                "success": True,
                "message": "No interfaces found for promiscuous mode",
            }

        # Render the service template
        template_path = (
            "salt://formulas/common/networking/files/promisc-mode.service.j2"
        )
        rendered = __salt__["slsutil.renderer"](
            template_path, context={"interfaces": list(interfaces)}
        )

        service_path = "/etc/systemd/system/promisc-mode.service"
        with open(service_path, "w") as f:
            f.write(rendered)

        # Reload systemd and enable/start the service
        __salt__["cmd.run"]("systemctl daemon-reload", python_shell=True)
        __salt__["cmd.run"](
            "systemctl enable --now promisc-mode.service", python_shell=True
        )

        return {
            "success": True,
            "message": f"Promiscuous mode service created and enabled for interfaces: {list(interfaces)}",
        }

    except Exception as e:
        return {
            "success": False,
            "message": f"Failed to enable promiscuous mode: {str(e)}",
        }
