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
    import xml.etree.ElementTree as ET

    import libvirt

    HAS_LIBVIRT = True
except ImportError:
    HAS_LIBVIRT = False

# Ensure Salt can find this module
__virtualname__ = "kinetic_libvirt"


@decorators.memoize
def __virtual__():
    """
    Check if the libvirt python library is available.
    """
    if HAS_LIBVIRT:
        return __virtualname__
    return (
        False,
        'The libvirt python library is not installed. Please install it using "pip install libvirt-python".',
    )


def connect_to_libvirt(connection_uri="qemu:///system", read_only=True):
    """
    Connect to a libvirt instance using the provided connection URI.

    Args:
        connection_uri (str): The libvirt connection URI (e.g., 'qemu+ssh://user@host/system')
        read_only (bool): Whether to open connection in read-only mode (default True)

    Returns:
        dict: A dictionary with 'success' (bool), 'connection' (libvirt.virConnect or None), and 'message' (str)
    """
    try:
        if read_only:
            conn = libvirt.openReadOnly(connection_uri)
        else:
            conn = libvirt.open(connection_uri)
        return {
            "success": True,
            "connection": conn,
            "message": f"Successfully connected to libvirt at {connection_uri} (read_only={read_only})",
        }
    except libvirt.libvirtError as e:
        return {
            "success": False,
            "connection": None,
            "message": f"Failed to connect to libvirt at {connection_uri}: {str(e)}",
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
    if not conn_result["success"]:
        return {"success": False, "macs": set(), "message": conn_result["message"]}

    conn = conn_result["connection"]
    mac_addresses = set()

    try:
        # Get active domains
        for domain_id in conn.listDomainsID():
            domain = conn.lookupByID(domain_id)
            xml_desc = domain.XMLDesc(0)
            root = ET.fromstring(xml_desc)
            for interface in root.findall(".//interface/mac"):
                mac = interface.get("address")
                if mac:
                    mac_addresses.add(mac.lower())

        # Get defined (inactive) domains
        for domain_name in conn.listDefinedDomains():
            domain = conn.lookupByName(domain_name)
            xml_desc = domain.XMLDesc(0)
            root = ET.fromstring(xml_desc)
            for interface in root.findall(".//interface/mac"):
                mac = interface.get("address")
                if mac:
                    mac_addresses.add(mac.lower())

        conn.close()
        return {
            "success": True,
            "macs": mac_addresses,
            "message": f"Found {len(mac_addresses)} existing MAC addresses",
        }
    except libvirt.libvirtError as e:
        conn.close()
        return {
            "success": False,
            "macs": set(),
            "message": f"Error retrieving MAC addresses: {str(e)}",
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
    if not macs_result["success"]:
        print(f"Warning: {macs_result['message']}. Proceeding without collision check.")
        existing_macs = set()
    else:
        existing_macs = macs_result["macs"]

    # Prefix for QEMU/KVM virtual machines (locally administered)
    prefix = [0x52, 0x54, 0x00]

    attempt = 0
    while attempt < max_attempts:
        # Generate random values for the last three octets
        random_octets = [random.randint(0x00, 0xFF) for _ in range(3)]
        # Combine prefix and random octets
        mac = prefix + random_octets
        # Format as a MAC address string
        mac_str = ":".join(f"{octet:02x}" for octet in mac)

        if mac_str.lower() not in existing_macs:
            return {
                "success": True,
                "mac": mac_str,
                "message": f"Generated unique MAC address: {mac_str}",
            }

        attempt += 1
        print(
            f"Collision detected for MAC {mac_str}, retrying ({attempt}/{max_attempts})"
        )

    return {
        "success": False,
        "mac": None,
        "message": f"Failed to generate a unique MAC address after {max_attempts} attempts",
    }


def check_qemu_address(connection_uri="qemu:///system"):
    """
    Check if a QEMU address (libvirt connection URI) is reachable and available.

    Args:
        connection_uri (str): The libvirt connection URI to test (e.g., 'qemu:///system' or 'qemu+ssh://user@host/system')

    Returns:
        dict: A dictionary with 'success' (bool), 'available' (bool), and 'message' (str)

    CLI Example:
        salt '*' kinetic-libvirt.check_qemu_address connection_uri='qemu:///system'
    """
    try:
        conn = libvirt.openReadOnly(connection_uri)
        conn.close()
        return {
            "success": True,
            "available": True,
            "message": f"QEMU address {connection_uri} is reachable and available",
        }
    except libvirt.libvirtError as e:
        return {
            "success": False,
            "available": False,
            "message": f"Failed to connect to QEMU address {connection_uri}: {str(e)}",
        }
    except Exception as e:
        return {
            "success": False,
            "available": False,
            "message": f"Error checking QEMU address {connection_uri}: {str(e)[:100]}...",
        }


def list_vms(connection_uri="qemu:///system"):
    """
    Retrieve a list of all defined and active virtual machines (domains) on the libvirt connection.

    Args:
        connection_uri (str): The libvirt connection URI (e.g., 'qemu+ssh://user@host/system')

    Returns:
        dict: A dictionary with 'success' (bool), 'vms' (list of VM names), and 'message' (str)
    """
    conn_result = connect_to_libvirt(connection_uri)
    if not conn_result["success"]:
        return {"success": False, "vms": [], "message": conn_result["message"]}

    conn = conn_result["connection"]
    vm_names = set()

    try:
        # Get active domains
        for domain_id in conn.listDomainsID():
            domain = conn.lookupByID(domain_id)
            vm_names.add(domain.name())

        # Get defined (inactive) domains
        for domain_name in conn.listDefinedDomains():
            vm_names.add(domain_name)

        conn.close()
        return {
            "success": True,
            "vms": sorted(list(vm_names)),
            "message": f"Found {len(vm_names)} virtual machines",
        }
    except libvirt.libvirtError as e:
        conn.close()
        return {
            "success": False,
            "vms": [],
            "message": f"Error retrieving virtual machines: {str(e)}",
        }


def pool_info(name, connection_uri="qemu:///system"):
    """
    Get information about a libvirt storage pool.

    Returns:
        dict: {'success': bool, 'exists': bool, 'active': bool, 'info': dict, 'message': str}
    """
    conn_result = connect_to_libvirt(connection_uri)
    if not conn_result["success"]:
        return {
            "success": False,
            "exists": False,
            "active": False,
            "info": {},
            "message": conn_result["message"],
        }

    conn = conn_result["connection"]
    try:
        try:
            pool = conn.storagePoolLookupByName(name)
            info = pool.info()
            active = pool.isActive() == 1
            conn.close()
            return {
                "success": True,
                "exists": True,
                "active": active,
                "info": info,
                "message": f"Pool {name} {'is' if active else 'is not'} active",
            }
        except libvirt.libvirtError:
            conn.close()
            return {
                "success": True,
                "exists": False,
                "active": False,
                "info": {},
                "message": f"Pool {name} does not exist",
            }
    except Exception as e:
        if "conn" in locals():
            conn.close()
        return {
            "success": False,
            "exists": False,
            "active": False,
            "info": {},
            "message": f"Error getting pool info: {str(e)}",
        }


def pool_define(name, ptype="dir", target="/kvm/vms", connection_uri="qemu:///system"):
    """
    Define a libvirt storage pool if it doesn't exist.

    Returns dict with success, changes, etc.
    """
    conn_result = connect_to_libvirt(connection_uri, read_only=False)
    if not conn_result["success"]:
        return {"success": False, "message": conn_result["message"]}

    conn = conn_result["connection"]
    try:
        # Check if pool already exists
        info = pool_info(name, connection_uri)
        if info.get("exists", False):
            conn.close()
            return {
                "success": True,
                "changed": False,
                "message": f"Pool {name} already exists",
            }

        # Define XML for directory pool
        xml = f"""<pool type='{ptype}'>
  <name>{name}</name>
  <target>
    <path>{target}</path>
  </target>
</pool>"""

        pool = conn.storagePoolDefineXML(xml, 0)
        conn.close()
        return {
            "success": True,
            "changed": True,
            "message": f"Successfully defined storage pool {name}",
        }
    except libvirt.libvirtError as e:
        if "conn" in locals() and conn:
            conn.close()
        return {
            "success": False,
            "message": f"Failed to define pool {name}: {str(e)}",
        }


def pool_start(name, connection_uri="qemu:///system"):
    """
    Start (activate) a libvirt storage pool if it is not active.
    """
    conn_result = connect_to_libvirt(connection_uri, read_only=False)
    if not conn_result["success"]:
        return {"success": False, "message": conn_result["message"]}

    conn = conn_result["connection"]
    try:
        pool = conn.storagePoolLookupByName(name)
        if pool.isActive() == 1:
            conn.close()
            return {
                "success": True,
                "changed": False,
                "message": f"Pool {name} is already active",
            }

        pool.create(0)
        conn.close()
        return {
            "success": True,
            "changed": True,
            "message": f"Successfully started storage pool {name}",
        }
    except libvirt.libvirtError as e:
        if "conn" in locals() and conn:
            conn.close()
        return {
            "success": False,
            "message": f"Failed to start pool {name}: {str(e)}",
        }


def volume_info(name, pool="vms", connection_uri="qemu:///system"):
    """
    Get information about a storage volume.

    Returns:
        dict: success, exists, info, message
    """
    conn_result = connect_to_libvirt(connection_uri)
    if not conn_result["success"]:
        return {
            "success": False,
            "exists": False,
            "info": {},
            "message": conn_result["message"],
        }

    conn = conn_result["connection"]
    try:
        try:
            pool_obj = conn.storagePoolLookupByName(pool)
            vol = pool_obj.storageVolLookupByName(name)
            info = vol.info()
            conn.close()
            return {
                "success": True,
                "exists": True,
                "info": info,
                "message": f"Volume {name} exists",
            }
        except libvirt.libvirtError:
            conn.close()
            return {
                "success": True,
                "exists": False,
                "info": {},
                "message": f"Volume {name} does not exist in pool {pool}",
            }
    except Exception as e:
        if "conn" in locals():
            conn.close()
        return {
            "success": False,
            "exists": False,
            "info": {},
            "message": str(e),
        }


def volume_create(
    name, pool="vms", capacity="20G", format="qcow2", connection_uri="qemu:///system"
):
    """
    Create a storage volume if it doesn't exist.
    """
    conn_result = connect_to_libvirt(connection_uri, read_only=False)
    if not conn_result["success"]:
        return {"success": False, "message": conn_result["message"]}

    conn = conn_result["connection"]
    try:
        # Check if volume already exists
        vol_info = volume_info(name, pool, connection_uri)
        if vol_info.get("exists", False):
            conn.close()
            return {
                "success": True,
                "changed": False,
                "message": f"Volume {name} already exists",
            }

        pool_obj = conn.storagePoolLookupByName(pool)

        # Convert capacity string to bytes (simple parser)
        if isinstance(capacity, str):
            if capacity.endswith("G"):
                size_bytes = int(capacity[:-1]) * 1024**3
            elif capacity.endswith("M"):
                size_bytes = int(capacity[:-1]) * 1024**2
            else:
                size_bytes = int(capacity)
        else:
            size_bytes = int(capacity)

        xml = f"""<volume>
  <name>{name}</name>
  <capacity unit='bytes'>{size_bytes}</capacity>
  <target>
    <format type='{format}'/>
  </target>
</volume>"""

        vol = pool_obj.createXML(xml, 0)
        conn.close()
        return {
            "success": True,
            "changed": True,
            "message": f"Successfully created volume {name} ({format}, {capacity})",
            "volume": name,
        }
    except libvirt.libvirtError as e:
        if "conn" in locals() and conn:
            conn.close()
        return {
            "success": False,
            "message": f"Failed to create volume {name}: {str(e)}",
        }


def define_xml(name, xml, connection_uri="qemu:///system"):
    """
    Define a domain (VM) from XML string. Checks if it already exists first.
    """
    conn_result = connect_to_libvirt(connection_uri, read_only=False)
    if not conn_result["success"]:
        return {"success": False, "message": conn_result["message"]}

    conn = conn_result["connection"]
    try:
        # Check if domain already exists
        try:
            conn.lookupByName(name)
            conn.close()
            return {
                "success": True,
                "changed": False,
                "message": f"Domain {name} already defined",
            }
        except libvirt.libvirtError:
            pass  # Domain doesn't exist - continue to define

        domain = conn.defineXML(xml)
        conn.close()
        return {
            "success": True,
            "changed": True,
            "message": f"Successfully defined domain {name}",
            "defined": True,
        }
    except libvirt.libvirtError as e:
        if "conn" in locals() and conn:
            conn.close()
        return {
            "success": False,
            "message": f"Failed to define domain {name}: {str(e)}",
        }
