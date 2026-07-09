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

__virtualname__ = 'kinetic_netplan'


def __virtual__():
    """
    Only load if netplan is available.
    """
    if os.path.exists('/usr/sbin/netplan'):
        return __virtualname__
    return (False, 'Netplan is not available on this system.')


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
            pillar_data = __salt__['pillar.get']('res-k8s', {})

        if not host_type:
            host_type = __salt__['grains.get']('type', 'default')

        config = {
            'network': {
                'version': 2,
                'renderer': 'networkd',
                'ethernets': {},
                'bonds': {},
                'bridges': {}
            }
        }

        networks = pillar_data.get('hosts', {}).get(host_type, {}).get('networks', {})

        for network_name, network_config in networks.items():
            if not network_config.get('managed', True):
                continue

            interfaces = network_config.get('interfaces', [])
            subnet_cidr = pillar_data.get('networking', {}).get('subnets', {}).get(network_name, '192.168.1.0/24')
            cidr_prefix = subnet_cidr.split('/')[1]

            # Get management IP for this host
            management_ip = pillar_data.get('bmh', {}).get(__salt__['grains.get']('id', ''), {}).get('network', {}).get('management_ip', '192.168.1.100')

            if len(interfaces) > 1:
                # Create bond
                bond_name = f'bond-{network_name}'
                config['network']['bonds'][bond_name] = {
                    'interfaces': interfaces,
                    'parameters': {
                        'mode': '802.3ad',
                        'mii-monitor-interval': 100,
                        'lacp-rate': 1
                    },
                    'mtu': 9000,
                    'dhcp4': False
                }

                interface_ref = bond_name
            else:
                interface_ref = interfaces[0]
                config['network']['ethernets'][interface_ref] = {
                    'dhcp4': False,
                    'mtu': 9000
                }

            if network_name == 'management':
                if host_type == 'controller':
                    # Management uses bridge on controllers
                    config['network']['bridges']['management_br'] = {
                        'interfaces': [interface_ref],
                        'addresses': [f'{management_ip}/{cidr_prefix}'],
                        'routes': [{
                            'to': 'default',
                            'via': pillar_data.get('dhcp-options', {}).get('mgmt_gateway', '192.168.1.1')
                        }],
                        'nameservers': {
                            'addresses': [pillar_data.get('dhcp-options', {}).get('dns', '8.8.8.8')]
                        },
                        'parameters': {
                            'stp': False,
                            'forward-delay': 0
                        }
                    }
                else:
                    # Non-controller management uses direct interface
                    if interface_ref not in config['network']['ethernets']:
                        config['network']['ethernets'][interface_ref] = {}
                    config['network']['ethernets'][interface_ref].update({
                        'addresses': [f'{management_ip}/{cidr_prefix}'],
                        'routes': [{
                            'to': 'default',
                            'via': pillar_data.get('dhcp-options', {}).get('mgmt_gateway', '192.168.1.1')
                        }],
                        'nameservers': {
                            'addresses': [pillar_data.get('dhcp-options', {}).get('dns', '8.8.8.8')]
                        }
                    })
            else:
                # Non-management networks use bridges with no IP
                bridge_name = f'{network_name}_br'
                config['network']['bridges'][bridge_name] = {
                    'interfaces': [interface_ref],
                    'dhcp4': False,
                    'parameters': {
                        'stp': False,
                        'forward-delay': 0
                    }
                }

        return {
            'success': True,
            'config': config,
            'message': 'Netplan configuration generated successfully'
        }

    except Exception as e:
        return {
            'success': False,
            'config': {},
            'message': f'Failed to generate Netplan configuration: {str(e)}'
        }


def apply_config(config=None, pillar_key='res-k8s'):
    """
    Apply Netplan configuration.

    Args:
        config (dict): Netplan config to apply. If None, generated from pillar.
        pillar_key (str): Pillar key to use for config generation.

    Returns:
        dict: Result with success, changes, and message.
    """
    try:
        if not config:
            config_result = generate_config()
            if not config_result['success']:
                return config_result
            config = config_result['config']

        # Write configuration to temporary file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            import yaml
            yaml.safe_dump(config, f, default_flow_style=False, sort_keys=False)
            temp_file = f.name

        # Copy to /etc/netplan/01-netcfg.yaml
        __salt__['file.copy'](temp_file, '/etc/netplan/01-netcfg.yaml', remove_source=True)
        __salt__['file.chown']('/etc/netplan/01-netcfg.yaml', 'root', 'root')
        __salt__['file.chmod']('/etc/netplan/01-netcfg.yaml', '600')

        # Apply configuration
        result = __salt__['cmd.run_all']('netplan apply', python_shell=False)

        if result['retcode'] == 0:
            return {
                'success': True,
                'changes': {'netplan': 'applied'},
                'message': 'Netplan configuration applied successfully'
            }
        else:
            return {
                'success': False,
                'changes': {},
                'message': f'Netplan apply failed: {result.get("stderr", result.get("stdout", "Unknown error"))}'
            }

    except Exception as e:
        return {
            'success': False,
            'changes': {},
            'message': f'Failed to apply Netplan configuration: {str(e)}'
        }


def promisc_mode(networks=None):
    """
    Enable promiscuous mode on specified networks using systemd service approach.

    Args:
        networks (list): List of network names to enable promiscuous mode on.
                         If None, uses all non-management networks from pillar.

    Returns:
        dict: Result with success and message.
    """
    try:
        if not networks:
            # Get all non-management networks from pillar
            pillar_data = __salt__['pillar.get']('res-k8s', {})
            host_type = __salt__['grains.get']('type', 'default')
            networks = []
            for network, config in pillar_data.get('hosts', {}).get(host_type, {}).get('networks', {}).items():
                if network != 'management' and config.get('managed', True):
                    networks.append(network)

        commands = []
        for network in networks:
            commands.append(f'ip link set "{network}_br" promisc on 2>/dev/null || true')
            if len(__salt__['pillar.get'](f'res-k8s:hosts:{host_type}:networks:{network}:interfaces', [])) > 1:
                commands.append(f'ip link set "bond-{network}" promisc on 2>/dev/null || true')

        # Execute all commands
        for cmd in commands:
            __salt__['cmd.run'](cmd, python_shell=True)

        return {
            'success': True,
            'message': f'Promiscuous mode enabled on networks: {networks}'
        }

    except Exception as e:
        return {
            'success': False,
            'message': f'Failed to enable promiscuous mode: {str(e)}'
        }
