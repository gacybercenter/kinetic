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
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        if "kinetic_libvirt.check_qemu_address" not in __salt__:
            ret["result"] = False
            ret["comment"] = (
                "The kinetic_libvirt module is not available. Ensure it is installed and synced."
            )
            ret["changes"] = {}
            return ret
        result = __salt__["kinetic_libvirt.check_qemu_address"](connection_uri)
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["success"]:
            ret["changes"] = {"available": result["available"]}
        else:
            ret["changes"] = {}
    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to check QEMU address {connection_uri}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

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
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        if "kinetic_libvirt.generate_unique_mac" not in __salt__:
            ret["result"] = False
            ret["comment"] = (
                "The kinetic_libvirt module is not available. Ensure it is installed and synced."
            )
            ret["changes"] = {}
            return ret
        result = __salt__["kinetic_libvirt.generate_unique_mac"](
            connection_uri, max_attempts
        )
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["success"]:
            ret["changes"] = {"mac": result["mac"]}
        else:
            ret["changes"] = {}
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to generate unique MAC address: {str(e)[:100]}..."
        ret["changes"] = {}

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
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        if "kinetic_libvirt.list_vms" not in __salt__:
            ret["result"] = False
            ret["comment"] = (
                "The kinetic_libvirt module is not available. Ensure it is installed and synced."
            )
            ret["changes"] = {}
            return ret
        result = __salt__["kinetic_libvirt.list_vms"](connection_uri)
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["success"]:
            ret["changes"] = {"vms": result["vms"]}
        else:
            ret["changes"] = {}
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to list virtual machines: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def pool_running(name, ptype="dir", target="/kvm/vms", connection="qemu:///system"):
    """
    Ensure a libvirt storage pool is defined and running.

    This replaces the deprecated virt.pool_running state.
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        if "kinetic_libvirt.pool_info" not in __salt__:
            ret["result"] = False
            ret["comment"] = (
                "The kinetic_libvirt module is not available. Ensure it is installed and synced."
            )
            ret["changes"] = {}
            return ret

        # First ensure connection is available
        conn_check = __salt__["kinetic_libvirt.check_qemu_address"](connection)
        if not conn_check.get("success", False):
            ret["result"] = False
            ret["comment"] = (
                f"Cannot connect to libvirt at {connection}: {conn_check.get('message', 'Unknown error')}"
            )
            return ret

        # Ensure pool is defined
        define_result = __salt__["kinetic_libvirt.pool_define"](
            name, ptype, target, connection
        )
        if not define_result.get("success", False):
            ret["result"] = False
            ret["comment"] = define_result.get("message", "Failed to define pool")
            return ret

        # Ensure pool is started (running)
        start_result = __salt__["kinetic_libvirt.pool_start"](name, connection)
        if not start_result.get("success", False):
            ret["result"] = False
            ret["comment"] = start_result.get("message", "Failed to start pool")
            return ret

        ret["result"] = True
        ret["comment"] = f"Storage pool {name} is defined and running"

        changes = {}
        if define_result.get("changed", False):
            changes["defined"] = True
        if start_result.get("changed", False):
            changes["started"] = True
        ret["changes"] = changes

        return ret
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to manage storage pool {name}: {str(e)[:100]}..."
        ret["changes"] = {}
        return ret


def volume_define(
    name, m_name, pool="vms", format="qcow2", size="20G", connection="qemu:///system"
):
    """
    Ensure a libvirt storage volume exists (creates it if it doesn't).

    This replaces the deprecated virt.volume_define module call.
    Note: The `name` parameter is the Salt state ID; `m_name` is the actual volume name.
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        if "kinetic_libvirt.volume_info" not in __salt__:
            ret["result"] = False
            ret["comment"] = (
                "The kinetic_libvirt module is not available. Ensure it is installed and synced."
            )
            ret["changes"] = {}
            return ret

        # Ensure connection is available
        conn_check = __salt__["kinetic_libvirt.check_qemu_address"](connection)
        if not conn_check.get("success", False):
            ret["result"] = False
            ret["comment"] = (
                f"Cannot connect to libvirt at {connection}: {conn_check.get('message', 'Unknown error')}"
            )
            return ret

        # Create volume (idempotent)
        create_result = __salt__["kinetic_libvirt.volume_create"](
            m_name, pool, size, format, connection
        )
        if not create_result.get("success", False):
            ret["result"] = False
            ret["comment"] = create_result.get("message", "Failed to create volume")
            return ret

        ret["result"] = True
        ret["comment"] = create_result.get(
            "message", f"Volume {m_name} is present in pool {pool}"
        )

        if create_result.get("changed", False):
            ret["changes"] = {"created": True, "volume": m_name, "pool": pool}
        else:
            ret["changes"] = {}

        return ret
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to define volume {m_name}: {str(e)[:100]}..."
        ret["changes"] = {}
        return ret


def define_xml_str(name, xml, connection="qemu:///system"):
    """
    Define a VM/domain from an XML string (idempotent).

    This replaces the deprecated virt.define_xml_str module call.
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        if "kinetic_libvirt.define_xml" not in __salt__:
            ret["result"] = False
            ret["comment"] = (
                "The kinetic_libvirt module is not available. Ensure it is installed and synced."
            )
            ret["changes"] = {}
            return ret

        # Ensure connection is available
        conn_check = __salt__["kinetic_libvirt.check_qemu_address"](connection)
        if not conn_check.get("success", False):
            ret["result"] = False
            ret["comment"] = (
                f"Cannot connect to libvirt at {connection}: {conn_check.get('message', 'Unknown error')}"
            )
            return ret

        define_result = __salt__["kinetic_libvirt.define_xml"](name, xml, connection)
        if not define_result.get("success", False):
            ret["result"] = False
            ret["comment"] = define_result.get("message", "Failed to define VM")
            return ret

        ret["result"] = True
        ret["comment"] = define_result.get("message", f"VM {name} is defined")

        if define_result.get("changed", False):
            ret["changes"] = {"defined": True}
        else:
            ret["changes"] = {}

        return ret
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to define VM from XML: {str(e)[:100]}..."
        ret["changes"] = {}
        return ret
