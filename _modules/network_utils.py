# -*- coding: utf-8 -*-
"""
SaltStack execution module for network utilities.

This module provides functions for network configuration tasks, such as converting CIDR prefix lengths to subnet masks.
"""

import salt.utils.decorators as decorators

# Ensure Salt can find this module
__virtualname__ = 'network_utils'

@decorators.memoize
def __virtual__():
    """
    This module has no external dependencies, so it should always load.
    """
    return __virtualname__

def cidr_to_netmask(cidr):
    """
    Convert a CIDR prefix length to a subnet mask.

    Args:
        cidr (int or str): The CIDR prefix length (e.g., 24 or '24').

    Returns:
        dict: A dictionary with 'success' (bool), 'netmask' (str), and 'message' (str).

    CLI Example:
        salt '*' network_utils.cidr_to_netmask 24
    """
    try:
        cidr = int(cidr)
        if not 0 <= cidr <= 32:
            return {
                'success': False,
                'netmask': '',
                'message': 'CIDR prefix length must be between 0 and 32'
            }

        # Create a 32-bit mask with 'cidr' number of 1s
        mask = (0xffffffff >> (32 - cidr)) << (32 - cidr)

        # Convert to dotted decimal format
        netmask = f"{(mask >> 24) & 0xff}.{(mask >> 16) & 0xff}.{(mask >> 8) & 0xff}.{mask & 0xff}"
        return {
            'success': True,
            'netmask': netmask,
            'message': f"Converted CIDR /{cidr} to netmask {netmask}"
        }

    except (ValueError, TypeError) as e:
        return {
            'success': False,
            'netmask': '',
            'message': f"Invalid CIDR value: {str(e)}"
        }