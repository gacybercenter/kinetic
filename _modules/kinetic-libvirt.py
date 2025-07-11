# -*- coding: utf-8 -*-
"""
SaltStack execution module for interacting with libvirt to generate unique MAC addresses
and manage virtual machine configurations.
This module connects to a libvirt instance to check for existing MAC addresses and generates
a new one that avoids collisions.
"""

import random
import salt.utils.decorators as decorators
try:
    import libvirt
    import xml.etree.ElementTree as ET
    HAS_LIBVIRT = True
except ImportError:
    HAS_LIBVIRT = False

# Ensure Salt can find this module
__virtualname__ = 'kinetic-libvirt'

@decorators.memoize
def __virtual__():
    """
    Check if the libvirt python library is available.
    """
    if HAS_LIBVIRT:
        return __virtualname__
    return (False, 'The libvirt python library is not installed. Please install it using "pip install libvirt-python".')

def connect_to_libvirt(connection_uri="qemu:///system"):
    """
    Connect to a libvirt instance using the provided connection URI.
    
    Args:
        connection_uri (str): The libvirt connection URI (e.g., 'qemu+ssh://user@host/system')
    
    Returns:
        dict: A dictionary with 'success' (bool), 'connection' (libvirt.virConnect or None), and 'message' (str)
    """
    try:
        conn = libvirt.openReadOnly(connection_uri)
        return {
            'success': True,
            'connection': conn,
            'message': f"Successfully connected to libvirt at {connection_uri}"
        }
    except libvirt.libvirtError as e:
        return {
            'success': False,
            'connection': None,
            'message': f"Failed to connect to libvirt at {connection_uri}: {str(e)}"
        }

def get_existing_mac_addresses(connection_uri="qemu:///system"):
    """
    Retrieve MAC addresses of all defined and active domains on the libvirt connection.
    
    Args:
        connection_uri (str): The libvirt connection URI (e.g., 'qemu+ssh://user@host/system')
    
    Returns:
        dict: A dictionary with 'success' (bool), 'macs' (set of MAC addresses), and 'message' (str)
    """
    conn_result = connect_to_libvirt(connection_uri)
    if not conn_result['success']:
        return {
            'success': False,
            'macs': set(),
            'message': conn_result['message']
        }
    
    conn = conn_result['connection']
    mac_addresses = set()
    
    try:
        # Get active domains
        for domain_id in conn.listDomainsID():
            domain = conn.lookupByID(domain_id)
            xml_desc = domain.XMLDesc(0)
            root = ET.fromstring(xml_desc)
            for interface in root.findall(".//interface/mac"):
                mac = interface.get('address')
                if mac:
                    mac_addresses.add(mac.lower())
        
        # Get defined (inactive) domains
        for domain_name in conn.listDefinedDomains():
            domain = conn.lookupByName(domain_name)
            xml_desc = domain.XMLDesc(0)
            root = ET.fromstring(xml_desc)
            for interface in root.findall(".//interface/mac"):
                mac = interface.get('address')
                if mac:
                    mac_addresses.add(mac.lower())
        
        conn.close()
        return {
            'success': True,
            'macs': mac_addresses,
            'message': f"Found {len(mac_addresses)} existing MAC addresses"
        }
    except libvirt.libvirtError as e:
        conn.close()
        return {
            'success': False,
            'macs': set(),
            'message': f"Error retrieving MAC addresses: {str(e)}"
        }

def generate_unique_mac(connection_uri="qemu:///system", max_attempts=100):
    """
    Generate a random MAC address for libvirt, avoiding collisions with existing MACs.
    Uses the prefix 52:54:00 and randomizes the last three octets.
    
    Args:
        connection_uri (str): The libvirt connection URI (e.g., 'qemu+ssh://user@host/system')
        max_attempts (int): Maximum number of attempts to generate a unique MAC
    
    Returns:
        dict: A dictionary with 'success' (bool), 'mac' (str or None), and 'message' (str)
    
    CLI Example:
        salt '*' kinetic-libvirt.generate_unique_mac connection_uri='qemu+ssh://user@remote-host/system'
    """
    # Get existing MAC addresses to avoid collisions
    macs_result = get_existing_mac_addresses(connection_uri)
    if not macs_result['success']:
        print(f"Warning: {macs_result['message']}. Proceeding without collision check.")
        existing_macs = set()
    else:
        existing_macs = macs_result['macs']
    
    # Prefix for QEMU/KVM virtual machines (locally administered)
    prefix = [0x52, 0x54, 0x00]
    
    attempt = 0
    while attempt < max_attempts:
        # Generate random values for the last three octets
        random_octets = [random.randint(0x00, 0xFF) for _ in range(3)]
        # Combine prefix and random octets
        mac = prefix + random_octets
        # Format as a MAC address string
        mac_str = ':'.join(f'{octet:02x}' for octet in mac)
        
        if mac_str.lower() not in existing_macs:
            return {
                'success': True,
                'mac': mac_str,
                'message': f"Generated unique MAC address: {mac_str}"
            }
        
        attempt += 1
        print(f"Collision detected for MAC {mac_str}, retrying ({attempt}/{max_attempts})")
    
    return {
        'success': False,
        'mac': None,
        'message': f"Failed to generate a unique MAC address after {max_attempts} attempts"
    }