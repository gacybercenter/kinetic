# -*- coding: utf-8 -*-
"""
SaltStack state module for interacting with libvirt to manage virtual machine configurations
and check connection availability.
"""

def check_qemu_address(name, connection_uri="qemu:///system"):
    """
    Check if a QEMU address (libvirt connection URI) is reachable and available.
    This is a read-only state for querying the availability of a QEMU address.

    name
        The name of the state (arbitrary, for SaltStack identification).

    connection_uri
        The libvirt connection URI to test (e.g., 'qemu:///system' or 'qemu+ssh://user@host/system').

    Example:
    .. code-block:: yaml

        check_qemu_system:
          libvirt.check_qemu_address:
            - connection_uri: qemu:///system
    """
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        if 'kinetic-libvirt.check_qemu_address' not in __salt__:
            ret['result'] = False
            ret['comment'] = "The kinetic-libvirt module is not available. Ensure it is installed and synced."
            ret['changes'] = {}
            return ret
        result = __salt__['kinetic-libvirt.check_qemu_address'](connection_uri)
        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['success']:
            ret['changes'] = {
                'available': result['available']
            }
        else:
            ret['changes'] = {}
    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to check QEMU address {connection_uri}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret

def generate_unique_mac(name, connection_uri="qemu:///system", max_attempts=100):
    """
    Generate a unique MAC address for libvirt, avoiding collisions with existing MACs.
    This state retrieves the generated MAC address or reports failure if a unique MAC cannot be generated.

    name
        The name of the state (arbitrary, for SaltStack identification).

    connection_uri
        The libvirt connection URI to connect to (e.g., 'qemu+ssh://user@host/system').

    max_attempts
        Maximum number of attempts to generate a unique MAC address. Defaults to 100.

    Example:
    .. code-block:: yaml

        generate_mac_address:
          libvirt.generate_unique_mac:
            - connection_uri: qemu:///system
            - max_attempts: 50
    """
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        if 'kinetic-libvirt.generate_unique_mac' not in __salt__:
            ret['result'] = False
            ret['comment'] = "The kinetic-libvirt module is not available. Ensure it is installed and synced."
            ret['changes'] = {}
            return ret
        result = __salt__['kinetic-libvirt.generate_unique_mac'](connection_uri, max_attempts)
        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['success']:
            ret['changes'] = {
                'mac': result['mac']
            }
        else:
            ret['changes'] = {}
    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to generate unique MAC address: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret
def list_vms(name, connection_uri="qemu:///system"):
    """
    Retrieve a list of all defined and active virtual machines (domains) from libvirt.
    
    name
        The name of the state (arbitrary, for SaltStack identification).
    
    connection_uri
        The libvirt connection URI to connect to (e.g., 'qemu+ssh://user@host/system').
    
    Example:
    .. code-block:: yaml
    
        list_virtual_machines:
          libvirt.list_vms:
            - connection_uri: qemu:///system
    """
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        if 'kinetic-libvirt.list_vms' not in __salt__:
            ret['result'] = False
            ret['comment'] = "The kinetic-libvirt module is not available. Ensure it is installed and synced."
            ret['changes'] = {}
            return ret
        result = __salt__['kinetic-libvirt.list_vms'](connection_uri)
        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['success']:
            ret['changes'] = {
                'vms': result['vms']
            }
        else:
            ret['changes'] = {}
    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to list virtual machines: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret