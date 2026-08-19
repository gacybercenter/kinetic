# -*- coding: utf-8 -*-
"""
SaltStack state module for managing Kubernetes resources using the kinetic_k8s execution module.

This module provides states for managing Bare Metal Hosts (BMH), Secrets for network data, userdata,
BMC authentication, and UUIDs, as well as querying hardware data from Kubernetes Custom Resources.
"""

import base64

from kubernetes import client, config
from kubernetes.client.rest import ApiException

__virtualname__ = "k8s"


def __virtual__():
    """
    Check if the kinetic_k8s execution module is available.
    """
    if "kinetic_k8s.secret_present" in __salt__:
        return __virtualname__
    return (False, "The kinetic_k8s execution module is not available.")


def _state_ret(name):
    """Return a standard SaltStack state return dict."""
    return {"name": name, "result": False, "comment": "", "changes": {}}


def _fetch_bmh_pillar(pillar_key, bmh_name, pillar_data=None):
    """
    Fetch and extract BMH pillar data for a specific host.

    If pillar_data is provided, return it unchanged with a debug message.
    Otherwise fetch from pillar using pillar_key and extract the host-specific
    entry by bmh_name, searching both 'bmh' sub-dict and top-level keys.

    Returns:
        tuple: (pillar_data dict, debug_msg str)

    Raises:
        SaltInvocationError: if pillar_key is None and pillar_data is None.
    """
    if pillar_data is not None:
        return pillar_data, "Pillar data provided directly; "

    if pillar_key is None:
        raise SaltInvocationError("Either pillar_data or pillar_key must be provided.")

    full_pillar_data = __salt__["pillar.get"](pillar_key, {})
    debug_msg = f"Pillar data fetched for key '{pillar_key}': type={type(full_pillar_data).__name__}; "

    if not isinstance(full_pillar_data, dict):
        return {}, debug_msg + f"value preview={repr(full_pillar_data)[:50]}...; "

    debug_msg += f"keys={list(full_pillar_data.keys())[:5]}; "
    if "bmh" in full_pillar_data and isinstance(full_pillar_data["bmh"], dict):
        debug_msg += f"bmh keys={list(full_pillar_data['bmh'].keys())[:5]}; "
        return full_pillar_data["bmh"].get(bmh_name, {}), debug_msg
    elif full_pillar_data.get(bmh_name) and isinstance(
        full_pillar_data.get(bmh_name), dict
    ):
        return full_pillar_data[
            bmh_name
        ], debug_msg + f"direct host data for {bmh_name} found; "
    else:
        return {}, debug_msg + f"no data for {bmh_name} found; "


def mac_by_interface_name(name, namespace, resource_name, interface_name):
    """
    Retrieve the MAC address of a specific network interface from a HardwareData Custom Resource in Kubernetes.
    This is a read-only state for querying data, not for enforcing a specific state.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace of the HardwareData resource.

    resource_name
        The name of the HardwareData resource.

    interface_name
        The name of the network interface to query.

    Example:
    .. code-block:: yaml

        get_mac_address:
          k8s.mac_by_interface_name:
            - namespace: baremetal-operator-system
            - resource_name: compute-133-26
            - interface_name: enp97s0f0
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.get_mac_by_interface_name"](
            namespace, resource_name, interface_name
        )
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["success"]:
            ret["changes"] = {"mac": result["mac"]}
        else:
            ret["changes"] = {}
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to retrieve MAC address: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def all_interfaces(name, namespace, resource_name):
    """
    Retrieve all network interfaces and their MAC addresses from a HardwareData Custom Resource in Kubernetes.
    This is a read-only state for querying data, not for enforcing a specific state.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace of the HardwareData resource.

    resource_name
        The name of the HardwareData resource.

    Example:
    .. code-block:: yaml

        get_all_interfaces:
          k8s.all_interfaces:
            - namespace: baremetal-operator-system
            - resource_name: compute-133-26
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.get_all_interfaces"](namespace, resource_name)
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["success"]:
            ret["changes"] = {"interfaces": result["interfaces"]}
        else:
            ret["changes"] = {}
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to retrieve interfaces: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def bmh_present(
    name,
    namespace,
    bmh_name,
    pillar_data=None,
    pillar_key="bmh",
    bmh_template_path="salt://formulas/bmo/files/bmh.j2",
):
    """
    Ensure that a Bare Metal Host (BMH) object in Kubernetes matches the desired state
    defined by pillar data and a Jinja2 template.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace of the Bare Metal Host resource.

    bmh_name
        The name of the Bare Metal Host resource.

    pillar_data
        Optional. Direct pillar data dictionary containing the BMH configuration.
        If not provided, data will be fetched using pillar_key and bmh_name.

    pillar_key
        Optional. The pillar key to fetch the BMH data from. Defaults to 'bmh'.
        Used if pillar_data is not provided.

    bmh_template_path
        Optional. Salt URI to the Jinja2 template file for BMH. Defaults to 'salt://formulas/bmo/files/bmh.j2'.

    Example:
    .. code-block:: yaml

        ensure_bmh:
          k8s.bmh_present:
            - namespace: baremetal-operator-system
            - bmh_name: compute-133-26
            - pillar_key: bmh
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        pillar_data, debug_pillar_msg = _fetch_bmh_pillar(
            pillar_key, bmh_name, pillar_data
        )

        # Call the execution module function
        result = __salt__["kinetic_k8s.bmh_present"](
            namespace, bmh_name, pillar_data, bmh_template_path
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        ret["comment"] += f" Debug: {debug_pillar_msg}"
        if result["updated"]:
            ret["changes"] = {"bmh_updated": True, "recreated": result["recreated"]}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure BMH {bmh_name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def networkdata_present(
    name,
    namespace,
    bmh_name,
    defaults,
    pillar_data=None,
    pillar_key="bmh",
    network_template_path="salt://formulas/bmo/files/network-data.j2",
):
    """
    Ensure that a network data Secret in Kubernetes matches the desired state
    defined by pillar data and a Jinja2 template.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace of the network data Secret.

    bmh_name
        The name of the Bare Metal Host resource (used for Secret naming).

    defaults
        A dictionary of default values for network configuration (e.g., interface, mac, ip, prefix, gateway, nameserver).

    pillar_data
        Optional. Direct pillar data dictionary containing the network configuration.
        If not provided, data will be fetched using pillar_key and bmh_name.

    pillar_key
        Optional. The pillar key to fetch the BMH data from. Defaults to 'bmh'.
        Used if pillar_data is not provided.

    network_template_path
        Optional. Salt URI to the Jinja2 template file for network data. Defaults to 'salt://formulas/bmo/files/network-data.j2'.

    Example:
    .. code-block:: yaml

        ensure_networkdata:
          k8s.networkdata_present:
            - namespace: baremetal-operator-system
            - bmh_name: compute-133-26
            - defaults:
                interface: eth0
                mac: 00:00:00:00:00:00
                ip: 192.168.1.100
                prefix: 24
                gateway: 192.168.1.1
                nameserver: 8.8.8.8
            - pillar_key: bmh
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        pillar_data, debug_pillar_msg = _fetch_bmh_pillar(
            pillar_key, bmh_name, pillar_data
        )

        # Call the execution module function
        result = __salt__["kinetic_k8s.networkdata_present"](
            namespace, bmh_name, defaults, pillar_data, network_template_path
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        ret["comment"] += f" Debug: {debug_pillar_msg}"
        if result["updated"]:
            ret["changes"] = {"networkdata_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure network data Secret for {bmh_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def userdata_present(
    name,
    namespace,
    bmh_name,
    pillar_data=None,
    pillar_key="bmh",
    userdata_template_path="salt://formulas/bmo/files/cloudinit.j2",
):
    """
    Ensure that a userdata Secret in Kubernetes matches the desired state
    defined by pillar data and a Jinja2 template.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace of the userdata Secret.

    bmh_name
        The name of the Bare Metal Host resource (used for Secret naming).

    pillar_data
        Optional. Direct pillar data dictionary containing the userdata configuration.
        If not provided, data will be fetched using pillar_key and bmh_name.

    pillar_key
        Optional. The pillar key to fetch the BMH data from. Defaults to 'bmh'.
        Used if pillar_data is not provided.

    userdata_template_path
        Optional. Salt URI to the Jinja2 template file for userdata. Defaults to 'salt://formulas/bmo/files/cloudinit.j2'.

    Example:
    .. code-block:: yaml

        ensure_userdata:
          k8s.userdata_present:
            - namespace: baremetal-operator-system
            - bmh_name: compute-133-26
            - pillar_key: bmh
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        pillar_data, debug_pillar_msg = _fetch_bmh_pillar(
            pillar_key, bmh_name, pillar_data
        )

        # Call the execution module function
        result = __salt__["kinetic_k8s.userdata_present"](
            namespace, bmh_name, pillar_data, userdata_template_path
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        ret["comment"] += f" Debug: {debug_pillar_msg}"
        if result["updated"]:
            ret["changes"] = {"userdata_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure userdata Secret for {bmh_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def host_bmc_auth_present(
    name,
    namespace,
    bmh_name,
    ipmi,
    pillar_data=None,
    pillar_key="bmh",
    bmc_auth_template_path="salt://formulas/bmo/files/bmc-auth.j2",
):
    """
    Ensure that a host-specific BMC authentication Secret in Kubernetes matches the desired state
    defined by pillar data and a Jinja2 template.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace of the Secret.

    bmh_name
        The name of the Bare Metal Host resource (used for Secret naming).

    ipmi
        Default IPMI password if not in pillar data.

    pillar_data
        Optional. Direct pillar data dictionary containing the BMC configuration.
        If not provided, data will be fetched using pillar_key and bmh_name.

    pillar_key
        Optional. The pillar key to fetch the BMH data from. Defaults to 'bmh'.
        Used if pillar_data is not provided.

    bmc_auth_template_path
        Optional. Salt URI to the Jinja2 template file for BMC auth Secret. Defaults to 'salt://formulas/bmo/files/bmc-auth.j2'.

    Example:
    .. code-block:: yaml

        ensure_bmc_auth:
          k8s.host_bmc_auth_present:
            - namespace: baremetal-operator-system
            - bmh_name: compute-133-26
            - ipmi: default_password
            - pillar_key: bmh
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        pillar_data, debug_pillar_msg = _fetch_bmh_pillar(
            pillar_key, bmh_name, pillar_data
        )

        # Call the execution module function
        result = __salt__["kinetic_k8s.host_bmc_auth_present"](
            namespace, bmh_name, ipmi, pillar_data, bmc_auth_template_path
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        ret["comment"] += f" Debug: {debug_pillar_msg}"
        if result["updated"]:
            ret["changes"] = {"bmc_auth_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure BMC auth Secret for {bmh_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def uuids_present(
    name,
    namespace,
    secret_name,
    pillar_data=None,
    pillar_key="bmh",
    deployment_name="salt-master",
    wait_timeout=300,
    wait_interval=10,
    salt_check_timeout=120,
    salt_check_interval=5,
    salt_check_key="bmh",
):
    """
    Ensure that a Kubernetes Secret with UUIDs is present and matches the desired state.
    If the secret is updated, the specified deployment will be restarted, and the state will wait
    for the deployment to become ready before completing. Attempts to extract UUIDs from 'bmh' in pillar data.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace where the Secret and Deployment reside.

    secret_name
        The name of the Secret in Kubernetes.

    pillar_data
        Optional. Direct pillar data dictionary containing the BMH data under 'bmh'.
        If not provided, data will be fetched using pillar_key.

    pillar_key
        Optional. The pillar key to fetch the data from. Defaults to 'bmh'.
        Used if pillar_data is not provided.

    deployment_name
        Optional. The name of the deployment to restart if the secret is updated. Defaults to 'salt-master'.

    wait_timeout
        Optional. Maximum time in seconds to wait for the deployment to become ready. Defaults to 300 (5 minutes).

    wait_interval
        Optional. Interval in seconds between checks for deployment readiness. Defaults to 10 seconds.

    salt_check_timeout
        Optional. Maximum time in seconds to wait for salt-master responsiveness. Defaults to 120 seconds.

    salt_check_interval
        Optional. Interval in seconds between salt-master responsiveness checks. Defaults to 5 seconds.

    salt_check_key
        Optional. The pillar key to fetch for checking salt-master responsiveness. Defaults to 'bmh'.

    Example:
    .. code-block:: yaml

        ensure_uuids_secret:
          k8s.uuids_present:
            - namespace: salt
            - secret_name: uuids
            - pillar_key: bmh
            - deployment_name: salt-master
            - wait_timeout: 300
            - wait_interval: 10
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        # If pillar_data is not provided, fetch it using pillar_key
        if pillar_data is None:
            if pillar_key is None:
                raise SaltInvocationError(
                    "Either pillar_data or pillar_key must be provided."
                )
            # Fetch the pillar data as a dictionary with the provided key
            pillar_data = __salt__["pillar.get"](pillar_key, {})
            debug_pillar_msg = f"Pillar data fetched for key '{pillar_key}': type={type(pillar_data).__name__}; "
            if isinstance(pillar_data, dict):
                debug_pillar_msg += f"keys={list(pillar_data.keys())[:5]}; "
                if "bmh" in pillar_data and isinstance(pillar_data["bmh"], dict):
                    debug_pillar_msg += (
                        f"bmh keys={list(pillar_data['bmh'].keys())[:5]}; "
                    )
                elif pillar_data and any(
                    isinstance(v, dict) and "uuid" in v for v in pillar_data.values()
                ):
                    debug_pillar_msg += f"direct host data detected in keys; "
            else:
                debug_pillar_msg += f"value preview={repr(pillar_data)[:50]}...; "
            # If the fetched data is not a dictionary, wrap it (unlikely but for safety)
            if not isinstance(pillar_data, dict):
                pillar_data = {pillar_key: pillar_data}

        # Call the execution module function
        result = __salt__["kinetic_k8s.uuids_secret_present"](
            namespace,
            secret_name,
            pillar_data,
            deployment_name,
            wait_timeout,
            wait_interval,
            salt_check_timeout,
            salt_check_interval,
            salt_check_key,
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if pillar_data is not None and debug_pillar_msg:
            ret["comment"] += f" Debug: {debug_pillar_msg}"
        if result["updated"]:
            ret["changes"] = {
                "secret_updated": True,
                "deployment_restarted": result["restarted"],
                "deployment_waited": result["waited"],
                "salt_responded": result["salt_responded"],
            }
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure Secret {secret_name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def mariadb_instance_present(
    name,
    namespace,
    instance_name,
    root_password,
    secret_name="mariadb-root-password",
    image="mariadb:10.6",
    storage_size="1Gi",
    storage_class="standard",
    pvc_name=None,
    replicas=1,
    limits_cpu="500m",
    limits_memory="512Mi",
    requests_cpu="200m",
    requests_memory="256Mi",
    admin_host_access="%",
):
    """
    Ensure that a MariaDB instance is present in Kubernetes using the MariaDB Operator.
    Creates or updates a root password Secret and the MariaDB instance Custom Resource with specified storage class, size, and optional PVC name.
    Checks if the associated PVC is available and ensures root user access from specified host.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace where the Secret and MariaDB instance reside.

    instance_name
        The name of the MariaDB instance in Kubernetes.

    root_password
        The root password for the MariaDB instance.

    secret_name
        Optional. The name of the Secret for the root password. Defaults to 'mariadb-root-password'.

    image
        Optional. The Docker image for MariaDB. Defaults to 'mariadb:10.6'.

    storage_size
        Optional. Storage size for MariaDB PVC. Defaults to '1Gi'.

    storage_class
        Optional. Storage class for MariaDB PVC. Defaults to 'standard'.

    pvc_name
        Optional. Name of an existing PVC to use for MariaDB storage. If not provided, the operator will create one based on storage_size and storage_class.

    replicas
        Optional. Number of replicas for MariaDB. Defaults to 1.

    limits_cpu
        Optional. CPU limit for MariaDB. Defaults to '500m'.

    limits_memory
        Optional. Memory limit for MariaDB. Defaults to '512Mi'.

    requests_cpu
        Optional. CPU request for MariaDB. Defaults to '200m'.

    requests_memory
        Optional. Memory request for MariaDB. Defaults to '256Mi'.

    admin_host_access
        Optional. Host or IP pattern to grant root access from. Defaults to '%'.

    Example:
    .. code-block:: yaml

        ensure_mariadb_instance:
          k8s.mariadb_instance_present:
            - namespace: baremetal-operator-system
            - instance_name: ironic-mariadb
            - root_password: mysecurepassword
            - secret_name: mariadb-root-password
            - image: mariadb:10.6
            - storage_size: 5Gi
            - storage_class: local-storage
            - pvc_name: my-custom-pvc
            - replicas: 1
            - limits_cpu: 500m
            - limits_memory: 512Mi
            - requests_cpu: 200m
            - requests_memory: 256Mi
            - admin_host_access: 192.168.1.41
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        # Call the execution module function
        result = __salt__["kinetic_k8s.mariadb_instance_present"](
            namespace=namespace,
            instance_name=instance_name,
            root_password=root_password,
            secret_name=secret_name,
            image=image,
            storage_size=storage_size,
            storage_class=storage_class,
            pvc_name=pvc_name,
            replicas=replicas,
            limits_cpu=limits_cpu,
            limits_memory=limits_memory,
            requests_cpu=requests_cpu,
            requests_memory=requests_memory,
            admin_host_access=admin_host_access,
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if (
            result["updated"]
            or result["secret_updated"]
            or result["root_access_updated"]
        ):
            ret["changes"] = {
                "instance_updated": result["updated"],
                "secret_updated": result["secret_updated"],
                "pvc_available": result["pvc_available"],
                "root_access_updated": result["root_access_updated"],
            }
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure MariaDB instance {instance_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def local_storage_pv_pvc_present(
    name,
    namespace,
    pv_name,
    pvc_name,
    storage_size="1Gi",
    node_name=None,
    path="/mnt/local-storage",
    storage_class="local-storage",
):
    """
    Ensure that a Persistent Volume (PV) and Persistent Volume Claim (PVC) are present in Kubernetes using a specified storage class for local storage.
    The PV is tied to a local path for local storage. Checks if the local path exists on the node before proceeding.
    Also checks if both resources exist and are bound.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace of the PVC (PV is cluster-wide but associated via PVC).

    pv_name
        The name of the Persistent Volume.

    pvc_name
        The name of the Persistent Volume Claim.

    storage_size
        Optional. Storage size for the PV and PVC. Defaults to '1Gi'.

    node_name
        Optional. The name of the node to bind the local storage PV to. Not used in this simplified version to avoid validation issues.

    path
        Optional. The host path on the node for local storage. Defaults to '/mnt/local-storage'.

    storage_class
        Optional. The storage class to use for the PV and PVC. Defaults to 'local-storage'.

    Example:
    .. code-block:: yaml

        ensure_local_storage:
          k8s.local_storage_pv_pvc_present:
            - namespace: baremetal-operator-system
            - pv_name: local-pv-1
            - pvc_name: local-pvc-1
            - storage_size: 5Gi
            - path: /mnt/local-storage
            - storage_class: local-storage
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        # Call the execution module function
        result = __salt__["kinetic_k8s.local_storage_pv_pvc_present"](
            namespace, pv_name, pvc_name, storage_size, node_name, path, storage_class
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["pv_updated"] or result["pvc_updated"]:
            ret["changes"] = {
                "pv_updated": result["pv_updated"],
                "pvc_updated": result["pvc_updated"],
                "bound": result["bound"],
            }
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure local storage PV {pv_name} and PVC {pvc_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def ironic_db_user_present(
    name,
    namespace,
    mariadb_name,
    mariadb_namespace,
    user_name,
    user_password,
    secret_name,
    database_name="ironic-database",
    host="%",
    max_user_connections=100,
    privileges=["ALL PRIVILEGES"],
    table="*",
):
    """
    Ensure that the necessary Kubernetes resources for an Ironic database user are present.
    This includes a Secret for user credentials, a User custom resource, and a Grant custom resource.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The namespace for the Secret, User, and Grant resources (typically Ironic namespace).

    mariadb_name
        The name of the MariaDB instance (Custom Resource) to reference.

    mariadb_namespace
        The namespace of the MariaDB instance.

    user_name
        The username for the database user (must match Secret data and User metadata name).

    user_password
        The password for the database user.

    secret_name
        The name of the Secret to store the user credentials.

    database_name
        Optional. The name of the database to grant privileges on. Defaults to 'ironic-database'.

    host
        Optional. The host pattern for user access. Defaults to '%'.

    max_user_connections
        Optional. Maximum connections for the user. Defaults to 100.

    privileges
        Optional. List of privileges to grant. Defaults to ['ALL PRIVILEGES'].

    table
        Optional. Table pattern for privileges. Defaults to '*'.

    Example:
    .. code-block:: yaml

        ensure_ironic_db_user:
          k8s.ironic_db_user_present:
            - namespace: test-ironic
            - mariadb_name: database-server
            - mariadb_namespace: mariadb
            - user_name: ironic-user
            - user_password: mysecurepassword
            - secret_name: ironic-user
            - database_name: ironic-database
            - host: '%'
            - max_user_connections: 100
            - privileges:
              - ALL PRIVILEGES
            - table: '*'
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.ironic_db_user_setup"](
            namespace=namespace,
            mariadb_name=mariadb_name,
            mariadb_namespace=mariadb_namespace,
            user_name=user_name,
            user_password=user_password,
            secret_name=secret_name,
            database_name=database_name,
            host=host,
            max_user_connections=max_user_connections,
            privileges=privileges,
            table=table,
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if (
            result["secret_updated"]
            or result["user_updated"]
            or result["grant_updated"]
        ):
            ret["changes"] = {
                "secret_updated": result["secret_updated"],
                "user_updated": result["user_updated"],
                "grant_updated": result["grant_updated"],
            }
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure Ironic DB user setup for {user_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def mariadb_database_present(
    name,
    namespace,
    database_name,
    mariadb_name,
    mariadb_namespace,
    character_set="utf8",
    collate="utf8_general_ci",
    cleanup_policy="Delete",
):
    """
    Ensure that a Database custom resource is present in Kubernetes using the MariaDB Operator.
    Creates or updates the Database resource to ensure a specific database exists in the MariaDB instance.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace for the Database resource (often the application namespace).

    database_name
        The name of the Database resource and the actual database in MariaDB.

    mariadb_name
        The name of the MariaDB instance to reference.

    mariadb_namespace
        The namespace of the MariaDB instance.

    character_set
        Optional. The character set for the database. Defaults to 'utf8'.

    collate
        Optional. The collation for the database. Defaults to 'utf8_general_ci'.

    cleanup_policy
        Optional. Cleanup policy for the resource. Defaults to 'Delete'.

    Example:
    .. code-block:: yaml

        ensure_ironic_database:
          k8s.mariadb_database_present:
            - namespace: test-ironic
            - database_name: ironic-database
            - mariadb_name: database-server
            - mariadb_namespace: mariadb
            - character_set: utf8
            - collate: utf8_general_ci
            - cleanup_policy: Delete
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.mariadb_database_present"](
            namespace=namespace,
            database_name=database_name,
            mariadb_name=mariadb_name,
            mariadb_namespace=mariadb_namespace,
            character_set=character_set,
            collate=collate,
            cleanup_policy=cleanup_policy,
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"database_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure Database {database_name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def tls_secret_present(
    name, namespace, secret_name, common_name="ironic-operator", validity_days=365
):
    """
    Ensure that a Kubernetes Secret with a TLS key pair is present.
    Generates a private key and self-signed certificate, then stores them in the Secret.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace where the Secret will be created.

    secret_name
        The name of the Secret to store the TLS key pair.

    common_name
        Optional. The Common Name (CN) for the certificate subject. Defaults to 'ironic-operator'.

    validity_days
        Optional. The number of days the certificate is valid for. Defaults to 365 (1 year).

    Example:
    .. code-block:: yaml

        ensure_tls_secret:
          k8s.tls_secret_present:
            - namespace: ironic-standalone-operator-system
            - secret_name: ironic-tls
            - common_name: ironic-operator
            - validity_days: 365
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.generate_tls_secret"](
            namespace=namespace,
            secret_name=secret_name,
            common_name=common_name,
            validity_days=validity_days,
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"secret_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure TLS Secret {secret_name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def ironic_operator_present(
    name,
    namespace="ironic-standalone-operator-system",
    deployment_name="ironic-standalone-operator-controller-manager",
    timeout=60,
):
    """
    Ensure that the Ironic Operator is installed and available in Kubernetes by checking the deployment status.

    Args:
        name (str): The name of the state (arbitrary, for SaltStack identification).
        namespace (str, optional): The Kubernetes namespace of the Ironic Operator deployment. Defaults to 'ironic-standalone-operator-system'.
        deployment_name (str, optional): The name of the Ironic Operator deployment. Defaults to 'ironic-standalone-operator-controller-manager'.
        timeout (int, optional): Maximum time in seconds to wait for the deployment to become available. Defaults to 60.

    Returns:
        dict: A dictionary with 'name' (str), 'result' (bool), 'comment' (str), and 'changes' (dict).

    Example:
    .. code-block:: yaml

        ensure_ironic_operator:
          k8s.ironic_operator_present:
            - namespace: ironic-standalone-operator-system
            - deployment_name: ironic-standalone-operator-controller-manager
            - timeout: 60
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.check_ironic_operator"](
            namespace, deployment_name, timeout
        )
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        # Only report changes if needed; keep empty for check-only state
        ret["changes"] = {}
        # If the state fails, append a message with the command to run
        if not result["success"]:
            ironic_op_dir = __salt__["pillar.get"](
                "ironic_op_dir", "<path-to-ironic-operator-repo>"
            )
            ret["comment"] += (
                f"; If the Ironic Operator is not installed, please run 'make install deploy' in the directory {ironic_op_dir} to install it."
            )
    except Exception as e:
        ret["result"] = False
        ironic_op_dir = __salt__["pillar.get"](
            "ironic_op_dir", "<path-to-ironic-operator-repo>"
        )
        ret["comment"] = (
            f"Failed to check Ironic Operator: {str(e)[:100]}...; If the Ironic Operator is not installed, please run 'make install deploy' in the directory {ironic_op_dir} to install it."
        )
        ret["changes"] = {}

    return ret


def ironic_instance_present(
    name,
    namespace,
    instance_name="ironic",
    database_secret_name="ironic-user",
    database_host="ironic-mariadb",
    database_port=3306,
    database_user="ironic",
    database_name="ironic",
    http_port=6385,
    networking_interface="",
    networking_ip="",
    networking_dhcp_range_start="",
    networking_dhcp_range_end="",
    networking_dhcp_range_gateway="",
    networking_dhcp_network_cidr="",
    networking_dhcp_serve_dns=False,
    networking_dhcp_dns_address="",
    inspection_dhcp_all_interfaces=False,
    enable_keepalived=False,
    keepalived_vip="",
    keepalived_interface="eth0",
    tls_secret_name="ironic-tls",
    ssh_public_key="",
    api_secret_name="ironic-api-creds",
    api_username="ironic",
    api_password="",
):
    """
    Ensure that an Ironic instance is present in Kubernetes using the Ironic Standalone Operator.
    Configures database connection, networking, optional Keepalived for HA, TLS, SSH key for deploy ramdisk, and API credentials.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace where the Ironic instance will reside.

    instance_name
        Optional. The name of the Ironic instance in Kubernetes. Defaults to 'ironic'.

    database_secret_name
        Optional. The name of the Secret for database credentials. Defaults to 'ironic-user'.

    database_host
        Optional. The hostname or service name of the database. Defaults to 'ironic-mariadb'.

    database_port
        Optional. The port for the database connection. Defaults to 3306.

    database_user
        Optional. The database user for Ironic. Defaults to 'ironic'.

    database_name
        Optional. The name of the database for Ironic. Defaults to 'ironic'.

    http_port
        Optional. The HTTP port for Ironic API. Defaults to 6385.

    networking_interface
        Optional. The interface for networking. Defaults to empty.

    networking_ip
        Optional. The IP address for networking. Defaults to empty.

    networking_dhcp_range_start
        Optional. Start of DHCP range for networking. Defaults to empty (no DHCP).

    networking_dhcp_range_end
        Optional. End of DHCP range for networking. Defaults to empty (no DHCP).

    networking_dhcp_range_gateway
        Optional. Gateway for DHCP range. Defaults to empty.

    networking_dhcp_network_cidr
        Optional. Network CIDR for DHCP range (e.g., '192.168.1.0/24'). Defaults to empty.

    networking_dhcp_serve_dns
        Optional. Whether to serve DNS via DHCP. Defaults to False.

    networking_dhcp_dns_address
        Optional. DNS address for DHCP if serve_dns is False. Defaults to empty.

    inspection_dhcp_all_interfaces
        Optional. Whether to DHCP all interfaces during inspection. Defaults to False.

    enable_keepalived
        Optional. Whether to enable Keepalived for high availability. Defaults to False.

    keepalived_vip
        Optional. Virtual IP for Keepalived. Required if enable_keepalived is True. Defaults to empty.

    keepalived_interface
        Optional. Interface for Keepalived. Defaults to 'eth0'.

    tls_secret_name
        Optional. The name of the Secret containing TLS certificates for Ironic. Defaults to 'ironic-tls'.

    ssh_public_key
        Optional. SSH public key to include in the deploy ramdisk for secure access. Defaults to empty.

    api_secret_name
        Optional. The name of the Secret containing API credentials for Ironic. Defaults to 'ironic-api-creds'.

    api_username
        Optional. The username for Ironic API access. Defaults to 'ironic'.

    api_password
        Optional. The password for Ironic API access. Defaults to empty (no password set).

    Example:
    .. code-block:: yaml

        ensure_ironic_instance:
          k8s.ironic_instance_present:
            - namespace: baremetal-operator-system
            - instance_name: ironic
            - database_secret_name: ironic-user
            - database_host: ironic-mariadb
            - database_port: 3306
            - database_user: ironic
            - database_name: ironic
            - http_port: 6385
            - networking_interface: eth0
            - networking_ip: 192.168.123.10
            - networking_dhcp_range_start: 192.168.123.100
            - networking_dhcp_range_end: 192.168.123.200
            - networking_dhcp_range_gateway: 192.168.123.1
            - networking_dhcp_network_cidr: 192.168.123.0/24
            - networking_dhcp_serve_dns: False
            - networking_dhcp_dns_address: 8.8.8.8
            - inspection_dhcp_all_interfaces: False
            - enable_keepalived: True
            - keepalived_vip: 192.168.123.10
            - keepalived_interface: eth0
            - tls_secret_name: ironic-tls
            - ssh_public_key: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user@example.com
            - api_secret_name: ironic-api-creds
            - api_username: ironic
            - api_password: mysecureapipassword
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.ironic_instance_present"](
            namespace=namespace,
            instance_name=instance_name,
            database_secret_name=database_secret_name,
            database_host=database_host,
            database_port=database_port,
            database_user=database_user,
            database_name=database_name,
            http_port=http_port,
            networking_interface=networking_interface,
            networking_ip=networking_ip,
            networking_dhcp_range_start=networking_dhcp_range_start,
            networking_dhcp_range_end=networking_dhcp_range_end,
            networking_dhcp_range_gateway=networking_dhcp_range_gateway,
            networking_dhcp_network_cidr=networking_dhcp_network_cidr,
            networking_dhcp_serve_dns=networking_dhcp_serve_dns,
            networking_dhcp_dns_address=networking_dhcp_dns_address,
            inspection_dhcp_all_interfaces=inspection_dhcp_all_interfaces,
            enable_keepalived=enable_keepalived,
            keepalived_vip=keepalived_vip,
            keepalived_interface=keepalived_interface,
            tls_secret_name=tls_secret_name,
            ssh_public_key=ssh_public_key,
            api_secret_name=api_secret_name,
            api_username=api_username,
            api_password=api_password,
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"] or result["api_secret_updated"]:
            ret["changes"] = {
                "instance_updated": result["updated"],
                "api_secret_updated": result["api_secret_updated"],
            }
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure Ironic instance {instance_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def image_server_present(
    name,
    namespace,
    deployment_name="ironic-image-server",
    service_name="ironic-image-server",
    image="python:3.9-slim",
    port=6180,
    tls_port=6183,
    storage_path="/images",
    pvc_name="ironic-images-pvc",
    storage_size="10Gi",
    storage_class="local-storage",
    service_type="ClusterIP",
    external_ip=None,
):
    """
    State to ensure that an image server for Ironic is present in Kubernetes.
    This state uses the kinetic_k8s.image_server_present execution module to manage the image server resources.

    Args:
        name (str): The name of the state (used for Salt state ID).
        namespace (str): The namespace for the Deployment, Service, and PVC in Kubernetes.
        deployment_name (str, optional): The name of the Deployment for the image server. Defaults to 'ironic-image-server'.
        service_name (str, optional): The name of the Service for the image server. Defaults to 'ironic-image-server'.
        image (str, optional): The Docker image to use for the image server. Defaults to 'python:3.9-slim'.
        port (int, optional): The HTTP port for serving images. Defaults to 6180.
        tls_port (int, optional): The HTTPS port for serving images (if TLS is configured). Defaults to 6183.
        storage_path (str, optional): The path inside the container to mount the image storage. Defaults to '/images'.
        pvc_name (str, optional): The name of the PersistentVolumeClaim for image storage. Defaults to 'ironic-images-pvc'.
        storage_size (str, optional): The storage size for the PVC. Defaults to '10Gi'.
        storage_class (str, optional): The storage class for the PVC. Defaults to 'local-storage'.
        service_type (str, optional): The type of Service to expose the image server. Options are 'ClusterIP', 'NodePort', or 'LoadBalancer'. Defaults to 'ClusterIP'.
        external_ip (str, optional): An external IP to assign to the Service if supported by the cluster. Defaults to None.

    Returns:
        dict: A dictionary with 'name', 'result', 'changes', and 'comment' as per Salt state conventions.

    Example:
        ensure_image_server:
          k8s.image_server_present:
            - name: ensure_image_server
            - namespace: baremetal-operator-system
            - service_type: LoadBalancer
            - external_ip: 192.168.1.100
    """
    ret = {"name": name, "result": False, "changes": {}, "comment": ""}

    try:
        result = __salt__["kinetic_k8s.image_server_present"](
            namespace=namespace,
            deployment_name=deployment_name,
            service_name=service_name,
            image=image,
            port=port,
            tls_port=tls_port,
            storage_path=storage_path,
            pvc_name=pvc_name,
            storage_size=storage_size,
            storage_class=storage_class,
            service_type=service_type,
            external_ip=external_ip,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("success", False):
            changes = {}
            if result.get("deployment_updated", False):
                changes["deployment"] = (
                    f"Deployment {deployment_name} updated or created"
                )
            if result.get("service_updated", False):
                changes["service"] = f"Service {service_name} updated or created"
            if result.get("pvc_updated", False):
                changes["pvc"] = f"PVC {pvc_name} updated or created"
            ret["changes"] = changes

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure image server: {str(e)[:100]}..."

    return ret


def bmh_state(name, namespace, bmh_name, desired_state):
    """
    Check if a Bare Metal Host (BMH) object in Kubernetes is in the specified state.
    This is a read-only state for querying the current provisioning status of a BMH.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace of the Bare Metal Host resource.

    bmh_name
        The name of the Bare Metal Host resource.

    desired_state
        The state to check for (e.g., 'provisioned', 'ready', 'error').

    Example:
    .. code-block:: yaml

        check_bmh_state:
          k8s.bmh_state:
            - namespace: baremetal-operator-system
            - bmh_name: compute-133-26
            - desired_state: provisioned
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.bmh_state"](namespace, bmh_name, desired_state)
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["success"]:
            ret["changes"] = {
                "in_state": result["in_state"],
                "current_state": result["current_state"],
            }
        else:
            ret["changes"] = {}
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to check BMH state for {bmh_name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def namespace_present(name, namespace):
    """
    Ensure that a Kubernetes namespace exists. If it does not exist, create it.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The name of the Kubernetes namespace to ensure exists.

    Example:
    .. code-block:: yaml

        ensure_namespace:
          k8s.namespace_present:
            - namespace: my-namespace
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.namespace_present"](namespace)
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"namespace_created": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure namespace {namespace}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def ceph_cluster_present(name, namespace, cluster_name, spec):
    """
    Ensure that a CephCluster Custom Resource exists in the specified namespace.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The namespace for the CephCluster resource.

    cluster_name
        The name of the CephCluster resource.

    spec
        The specification dictionary for the CephCluster resource.

    Example:
    .. code-block:: yaml

        ensure_ceph_cluster:
          k8s.ceph_cluster_present:
            - namespace: rook-ceph
            - cluster_name: rook-ceph
            - spec:
                cephVersion:
                  image: quay.io/ceph/ceph:v19.2.3
                dataDirHostPath: /var/lib/rook
                storage:
                  useAllNodes: false
                  useAllDevices: false
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.ceph_cluster_present"](
            namespace, cluster_name, spec
        )
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"ceph_cluster_updated": True}
        else:
            ret["changes"] = {}
    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure CephCluster {cluster_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def configmap_present(
    name, namespace, configmap_name, data, labels=None, annotations=None
):
    """
    Ensure that a Kubernetes ConfigMap exists in the specified namespace. If it does not exist, create it.
    If it exists, update it if the data, labels, or annotations differ.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace for the ConfigMap.

    configmap_name
        The name of the ConfigMap resource in Kubernetes.

    data
        The data to store in the ConfigMap (dictionary of key-value pairs).

    labels
        Optional. Labels to apply to the ConfigMap. Defaults to None.

    annotations
        Optional. Annotations to apply to the ConfigMap. Defaults to None.

    Example:
    .. code-block:: yaml

        ensure_configmap:
          k8s.configmap_present:
            - namespace: efk
            - configmap_name: opensearch-dashboards-config
            - data:
                opensearch_dashboards.yml: |
                  opensearch.hosts: ["https://opensearch-cluster-master.efk.svc.cluster.local:9200"]
                  opensearch.username: "admin"
                  opensearch.password: "YourStrongPassword123!"
                  opensearch.ssl.verificationMode: none
                  opensearch.ssl.certificateAuthorities: ["/usr/share/opensearch-dashboards/config/certs/ca.crt"]
                  logging.verbose: true
            - labels:
                app: opensearch-dashboards
            - annotations:
                description: Configuration for OpenSearch Dashboards
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.configmap_present"](
            namespace=namespace,
            name=configmap_name,
            data=data,
            labels=labels,
            annotations=annotations,
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"configmap_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure ConfigMap {configmap_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def service_present(
    name,
    namespace,
    service_name,
    service_type="LoadBalancer",
    selector=None,
    ports=None,
    annotations=None,
    external_ip=None,
):
    """
    Ensure that a Kubernetes Service is present in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace for the Service.

    service_name
        The name of the Service resource in Kubernetes.

    service_type
        Optional. The type of Service ('ClusterIP', 'NodePort', 'LoadBalancer'). Defaults to 'LoadBalancer'.

    selector
        Optional. The selector labels to match target pods (dictionary). Defaults to None.

    ports
        Optional. List of port mappings, each with 'name', 'port', 'targetPort', and 'protocol'. Defaults to HTTP (80) and HTTPS (443).

    annotations
        Optional. Annotations to apply to the Service (e.g., for MetalLB IP pool). Defaults to None.

    external_ip
        Optional. An external IP to assign to the Service if supported by the cluster. Defaults to None.

    Example:
    .. code-block:: yaml

        ensure_openstack_public_service:
          k8s.service_present:
            - namespace: openstack
            - service_name: openstack-public
            - service_type: LoadBalancer
            - selector:
                app.kubernetes.io/name: ingress-nginx
                app.kubernetes.io/instance: ingress-nginx
            - ports:
                - name: http
                  port: 80
                  targetPort: 80
                  protocol: TCP
                - name: https
                  port: 443
                  targetPort: 443
                  protocol: TCP
            - annotations:
                metallb.universe.tf/address-pool: default
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.service_present"](
            namespace=namespace,
            service_name=service_name,
            service_type=service_type,
            selector=selector,
            ports=ports,
            annotations=annotations,
            external_ip=external_ip,
        )

        # Ensure 'success' key exists in result, default to False if not
        success = result.get("success", False)
        ret["result"] = success
        ret["comment"] = result.get("message", "Unknown error in service operation")
        if result.get("updated", False):
            ret["changes"] = {"service_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure Service {service_name}: Exception occurred: {str(e)[:200]}..."
        )
        ret["changes"] = {}

    return ret


def node_label_present(name, namespace, node_name, labels):
    """
    Ensure that the specified labels are present on a Kubernetes node.
    If a label key exists with a different value, it will be updated. If it doesn't exist, it will be added.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The namespace is not used for node operations but kept for consistency.

    node_name
        The name of the Kubernetes node to apply labels to.

    labels
        A dictionary of key-value pairs representing the labels to apply to the node.

    Example:
    .. code-block:: yaml

        ensure_node_labels:
          k8s.node_label_present:
            - namespace: unused-namespace
            - node_name: k8s-node-1
            - labels:
                key1: value1
                key2: value2
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.node_label_present"](
            namespace, node_name, labels
        )
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"labels_updated": result["changes"]}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily
    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure labels on node {node_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def metallb_pool_present(
    name, namespace, pool_name, addresses, metallb_namespace="metallb-system"
):
    """
    Ensure that a MetalLB IPAddressPool Custom Resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The namespace for the IPAddressPool resource (unused, kept for consistency).

    pool_name
        The name of the IPAddressPool resource.

    addresses
        List of IP address ranges (e.g., ["10.150.1.43-10.150.1.50"]).

    metallb_namespace
        Optional. The namespace where MetalLB is installed. Defaults to 'metallb-system'.

    Example:
    .. code-block:: yaml

        ensure_metallb_pool:
          k8s.metallb_pool_present:
            - namespace: unused-namespace
            - pool_name: default
            - addresses:
                - 10.150.1.43-10.150.1.50
                - 10.150.1.247-10.150.1.247
            - metallb_namespace: metallb-system
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.metallb_pool_present"](
            namespace, pool_name, addresses, metallb_namespace
        )
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"ingress_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily
    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure IPAddressPool {pool_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def metallb_l2_advertisement_present(
    name, namespace, advertisement_name, pool_names, metallb_namespace="metallb-system"
):
    """
    Ensure that a MetalLB L2Advertisement Custom Resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The namespace for the L2Advertisement resource (unused, kept for consistency).

    advertisement_name
        The name of the L2Advertisement resource.

    pool_names
        List of IPAddressPool names to advertise.

    metallb_namespace
        Optional. The namespace where MetalLB is installed. Defaults to 'metallb-system'.

    Example:
    .. code-block:: yaml

        ensure_metallb_advertisement:
          k8s.metallb_l2_advertisement_present:
            - namespace: unused-namespace
            - advertisement_name: default-l2
            - pool_names:
                - default
            - metallb_namespace: metallb-system
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.metallb_l2_advertisement_present"](
            namespace, advertisement_name, pool_names, metallb_namespace
        )
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"advertisement_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily
    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure L2Advertisement {advertisement_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def certmanager_issuer_present(
    name, namespace, issuer_name, issuer_kind="Issuer", spec=None
):
    """
    Ensure that a Cert-Manager Issuer or ClusterIssuer resource is present in Kubernetes.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace for the Issuer resource. Use 'cluster-wide' for ClusterIssuer.

    issuer_name
        The name of the Issuer or ClusterIssuer resource.

    issuer_kind
        Optional. The kind of issuer, either 'Issuer' or 'ClusterIssuer'. Defaults to 'Issuer'.

    spec
        Optional. The specification dictionary for the Issuer resource. If not provided, a basic self-signed issuer will be created.

    Example:
    .. code-block:: yaml

        ensure_selfsigned_issuer:
          k8s.certmanager_issuer_present:
            - namespace: cert-manager
            - issuer_name: selfsigned-issuer
            - issuer_kind: Issuer
            - spec:
                selfSigned: {}

        ensure_ca_issuer:
          k8s.certmanager_issuer_present:
            - namespace: cert-manager
            - issuer_name: ca-issuer
            - issuer_kind: Issuer
            - spec:
                ca:
                  secretName: ca-key-pair
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.certmanager_issuer_present"](
            namespace, issuer_name, issuer_kind, spec
        )
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {f"{issuer_kind.lower()}_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily
    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure Ingress {name} in namespace {namespace}: Full Exception: {str(e)}"
        )
        ret["changes"] = {}
        __salt__["log.error"](f"Exception in ingress_present: {str(e)}")

    return ret


def ingress_present(
    name,
    namespace,
    hosts,
    tls=None,
    ingress_class_name=None,
    annotations=None,
    **kwargs,
):
    """
    Ensures that an Ingress resource is present in the specified namespace.
    This is useful for routing external traffic to services within the cluster.

    Args:
        name (str): The name of the Ingress resource.
        namespace (str): The namespace in which the Ingress should exist.
        hosts (list): List of hostnames or host configurations for the Ingress rules.
        tls (list, optional): List of TLS configurations, each containing secretName and hosts.
        ingress_class_name (str, optional): The name of the IngressClass to use.
        annotations (dict, optional): Additional annotations for the Ingress.
        **kwargs: Additional arguments to pass to the Kubernetes API.

    Returns:
        dict: A dictionary containing the result of the operation.
    """
    ret = {"name": name, "result": None, "changes": {}, "comment": ""}

    try:
        # Delegate to the execution module for managing the Ingress
        result = __salt__["kinetic_k8s.ingress_present"](
            name=name,
            namespace=namespace,
            hosts=hosts,
            tls=tls,
            ingress_class_name=ingress_class_name,
            annotations=annotations,
            **kwargs,
        )

        if result.get("result"):
            ret["result"] = True
            if "created" in result.get("changes", {}):
                ret["changes"] = {"created": f"Ingress {name} in namespace {namespace}"}
                ret["comment"] = f"Ingress {name} created in namespace {namespace}."
            elif "updated" in result.get("changes", {}):
                ret["changes"] = {"updated": f"Ingress {name} in namespace {namespace}"}
                ret["comment"] = f"Ingress {name} updated in namespace {namespace}."
            else:
                ret["comment"] = (
                    f"Ingress {name} already exists in namespace {namespace} with the desired configuration."
                )
        else:
            ret["result"] = False
            ret["comment"] = result.get(
                "comment", f"Failed to manage Ingress {name} in namespace {namespace}."
            )
    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Error managing Ingress {name} in namespace {namespace}: {str(e)[:50]}..."
        )

    return ret


def certmanager_certificate_present(
    name,
    certificate_name,
    namespace,
    secret_name,
    issuer_name,
    issuer_kind,
    common_name,
    dns_names=None,
    ip_addresses=None,
    duration="2160h",
    renew_before="360h",
    is_ca=False,
    subject=None,
    private_key=None,
    usages=None,
):
    """
    Ensure a cert-manager Certificate exists in the specified Kubernetes namespace.

    name
        The name of the state (arbitrary, for SaltStack identification).

    certificate_name
        The name of the Certificate resource to create or update.

    namespace
        The Kubernetes namespace for the Certificate.

    secret_name
        The name of the Secret where the certificate will be stored.

    issuer_name
        The name of the Issuer or ClusterIssuer to use.

    issuer_kind
        The kind of the Issuer (e.g., 'Issuer' or 'ClusterIssuer').

    common_name
        The common name (CN) for the certificate.

    dns_names
        Optional. List of DNS names (SANs) for the certificate. Defaults to None.

    ip_addresses
        Optional. List of IP addresses (SANs) for the certificate. Defaults to None.

    duration
        Optional. Duration of the certificate validity (e.g., '2160h'). Defaults to '2160h'.

    renew_before
        Optional. Time before expiration to renew the certificate (e.g., '360h'). Defaults to '360h'.

    is_ca
        Optional. If True, the certificate will be marked as a CA certificate. Defaults to False.

    subject
        Optional. Subject block (organizations, organizationalUnits, countries, …).

    private_key
        Optional. Private-key settings (algorithm, size, encoding).

    usages
        Optional. Extended key usages list.

    Example:
    .. code-block:: yaml

        ensure_ca_cert:
          k8s.certmanager_certificate_present:
            - certificate_name: ca-cert
            - namespace: cert-manager
            - secret_name: ca-cert-secret
            - issuer_name: selfsigned-issuer
            - issuer_kind: Issuer
            - common_name: "My CA"
            - dns_names:
              - ca.local
            - duration: 8760h
            - renew_before: 720h
            - is_ca: True
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        # Log input parameters for debugging
        __salt__["log.debug"](
            f"Calling certmanager_certificate_present with parameters: "
            f"name={certificate_name}, namespace={namespace}, secret_name={secret_name}, "
            f"issuer_name={issuer_name}, issuer_kind={issuer_kind}, common_name={common_name}, "
            f"dns_names={dns_names}, ip_addresses={ip_addresses}, duration={duration}, "
            f"renew_before={renew_before}, is_ca={is_ca}, "
            f"subject={subject}, private_key={private_key}, usages={usages}"
        )

        # Debug available modules for troubleshooting
        available_modules = [mod for mod in __salt__.keys() if "kinetic" in mod]
        __salt__["log.debug"](
            f"Available modules with 'kinetic' in name: {available_modules}"
        )

        if "kinetic_k8s.certmanager_certificate_present" in __salt__:
            result = __salt__["kinetic_k8s.certmanager_certificate_present"](
                name=certificate_name,
                namespace=namespace,
                secret_name=secret_name,
                issuer_name=issuer_name,
                issuer_kind=issuer_kind,
                common_name=common_name,
                dns_names=dns_names,
                ip_addresses=ip_addresses,
                duration=duration,
                renew_before=renew_before,
                is_ca=is_ca,
                subject=subject,
                private_key=private_key,
                usages=usages,
            )
        else:
            ret["result"] = False
            ret["comment"] = (
                "Module kinetic_k8s.certmanager_certificate_present is not available. Please ensure the module is synced to the minion."
            )
            ret["changes"] = {}
            return ret

        # Log the result for debugging
        __salt__["log.debug"](
            f"Result from kinetic_k8s.certmanager_certificate_present: {result}"
        )

        # Check if result is None or not a dictionary
        if result is None or not isinstance(result, dict):
            raise ValueError(
                f"Unexpected return type from kinetic_k8s.certmanager_certificate_present: {type(result)}"
            )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "No message provided.")
        if result.get("updated", False):
            ret["changes"] = {"certificate_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure Certificate {certificate_name} in namespace {namespace}: Full Exception: {str(e)}"
        )
        ret["changes"] = {}
        __salt__["log.error"](f"Exception in certmanager_certificate_present: {str(e)}")

    return ret


def cnpg_cluster_present(name, namespace, cluster_name, spec):
    """
    Ensure that a CloudNativePG Cluster Custom Resource is present in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace for the Cluster resource.

    cluster_name
        The name of the Cluster resource.

    spec
        The specification for the Cluster resource, including instances, imageName, storage, etc.

    Example:
    .. code-block:: yaml

        ensure_cnpg_cluster:
          k8s.cnpg_cluster_present:
            - namespace: cnpg-system
            - cluster_name: my-cluster
            - spec:
                instances: 2
                imageName: ghcr.io/cloudnative-pg/postgres:16
                storage:
                  size: 10Gi
                  storageClass: standard
                resources:
                  limits:
                    cpu: 1000m
                    memory: 1024Mi
                  requests:
                    cpu: 500m
                    memory: 512Mi
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.cnpg_cluster_present"](
            namespace, cluster_name, spec
        )
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"cluster_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure Cluster {cluster_name}: {str(e)[:100]}..."


def opensearch_cluster_present(name, namespace, cluster_name, spec):
    """
    Ensure that an OpenSearchCluster Custom Resource is present in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace for the OpenSearchCluster resource.

    cluster_name
        The name of the OpenSearchCluster resource.

    spec
        The specification for the OpenSearchCluster resource.

    Example:
    .. code-block:: yaml

        ensure_opensearch_cluster:
          k8s.opensearch_cluster_present:
            - namespace: efk
            - cluster_name: opensearch
            - spec:
                general:
                  version: "2.11.0"
                  image: "docker.io/opensearchproject/opensearch"
                  additionalConfig:
                    logger.securityjwt.level: trace
                nodePools:
                  - component: masters
                    replicas: 3
                    roles:
                      - master
                      - data
                      - ingest
                    diskSize: "10Gi"
                    resources:
                      requests:
                        memory: "8Gi"
                        cpu: "2"
                      limits:
                        memory: "8Gi"
                        cpu: "2"
                security:
                  config:
                    securityConfigSecret:
                      name: opensearch-security-config
                  tls:
                    http:
                      enabled: true
                      generate: false
                      secret:
                        name: opensearch-tls-secret
                    transport:
                      enabled: true
                      generate: false
                      secret:
                        name: opensearch-tls-secret
                      perNode: true
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.opensearch_cluster_present"](
            namespace, cluster_name, spec
        )
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"cluster_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure OpenSearchCluster {cluster_name}: {str(e)[:100]}..."

    return ret


def opensearch_user_present(
    name, namespace, user_name, cluster_name, password_secret_name, password_key="password"
):
    """
    Ensure that an OpensearchUser Custom Resource exists.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace for the OpensearchUser resource.

    user_name
        The name of the OpensearchUser resource.

    cluster_name
        The name of the target OpenSearchCluster.

    password_secret_name
        Name of the Secret containing the user's password.

    password_key
        Key inside the Secret that holds the password. Defaults to 'password'.
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.opensearch_user_present"](
            namespace, user_name, cluster_name, password_secret_name, password_key
        )
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result.get("updated"):
            ret["changes"] = {"user_updated": True}
        else:
            ret["changes"] = {}
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure OpensearchUser {user_name}: {str(e)[:100]}..."

    return ret


def secret_present(
    name,
    namespace,
    secret_name,
    data,
    secret_type="Opaque",
    labels=None,
    annotations=None,
):
    """
    Ensure that a Kubernetes Secret exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if the data, labels, or annotations differ.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace for the Secret.

    secret_name
        The name of the Secret resource in Kubernetes.

    data
        The data to store in the Secret (dictionary of key-value pairs).

    secret_type
        Optional. The type of Secret (e.g., 'Opaque', 'kubernetes.io/tls'). Defaults to 'Opaque'.

    labels
        Optional. Labels to apply to the Secret. Defaults to None.

    annotations
        Optional. Annotations to apply to the Secret. Defaults to None.

    Example:
    .. code-block:: yaml

        ensure_secret:
          k8s.secret_present:
            - namespace: my-namespace
            - secret_name: my-secret
            - data:
                key1: value1
                key2: value2
            - secret_type: Opaque
            - labels:
                app: my-app
            - annotations:
                description: My secret description
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.secret_present"](
            namespace=namespace,
            secret_name=secret_name,
            data=data,
            secret_type=secret_type,
            labels=labels,
            annotations=annotations,
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"secret_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure Secret {secret_name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def keycloak_cluster_present(
    name,
    namespace,
    hostname,
    cluster_name,
    start_optimized=False,
    instances=1,
    image=None,
    db_vendor="postgres",
    db_host=None,
    db_port=5432,
    db_name=None,
    db_user_name_secret_name=None,
    db_user_name_secret_key="username",
    db_password_secret_name=None,
    db_password_secret_key="password",
    ingress_enabled=False,
    proxy_headers=None,
    tls_secret=None,
    truststores=None,
):
    """
    Ensure a Keycloak Cluster exists in the specified Kubernetes namespace.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace for the Keycloak Cluster.

    hostname
        The hostname for the Keycloak instance.

    cluster_name
        The name of the Keycloak Cluster resource.

    start_optimized
        Optional. Whether to start Keycloak in optimized mode. Defaults to False.

    instances
        Optional. Number of Keycloak instances. Defaults to 1.

    image
        Optional. Docker image for Keycloak. Defaults to None (uses operator default).

    db_vendor
        Optional. Database vendor (e.g., 'postgres'). Defaults to 'postgres'.

    db_host
        Optional. Database host. Defaults to None.

    db_port
        Optional. Database port. Defaults to 5432.

    db_name
        Optional. Database name. Defaults to None.

    db_user_name_secret_name
        Optional. Secret name for database username. Defaults to None.

    db_user_name_secret_key
        Optional. Key in the secret for username. Defaults to 'username'.

    db_password_secret_name
        Optional. Secret name for database password. Defaults to None.

    db_password_secret_key
        Optional. Key in the secret for password. Defaults to 'password'.

    ingress_enabled
        Optional. Whether to enable ingress. Defaults to False.

    proxy_headers
        Optional. Proxy headers configuration (e.g., 'forwarded'). Defaults to None.

    tls_secret
        Optional. Name of the TLS secret for HTTPS. Defaults to None.

    truststores
        Optional. Dictionary mapping truststore names to configurations with secret names. Defaults to None.
            Example: {'my-truststore': {'secret': {'name': 'my-secret'}}}

    Example:
    .. code-block:: yaml

        ensure_keycloak_cluster:
          k8s.keycloak_cluster_present:
            - namespace: keycloak
            - hostname: keycloak.example.com
            - cluster_name: keycloak-cluster
            - instances: 2
            - image: quay.io/keycloak/keycloak:22.0.1
            - db_vendor: postgres
            - db_host: postgres-rw
            - db_port: 5432
            - db_name: keycloak
            - db_user_name_secret_name: keycloak-db-cred
            - db_user_name_secret_key: username
            - db_password_secret_name: keycloak-db-cred
            - db_password_secret_key: password
            - ingress_enabled: False
            - proxy_headers: forwarded
            - tls_secret: keycloak-tls
            - truststores:
                my-truststore:
                  secret:
                    name: my-secret
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.keycloak_cluster_present"](
            namespace=namespace,
            hostname=hostname,
            cluster_name=cluster_name,
            start_optimized=start_optimized,
            instances=instances,
            image=image,
            db_vendor=db_vendor,
            db_host=db_host,
            db_port=db_port,
            db_name=db_name,
            db_user_name_secret_name=db_user_name_secret_name,
            db_user_name_secret_key=db_user_name_secret_key,
            db_password_secret_name=db_password_secret_name,
            db_password_secret_key=db_password_secret_key,
            ingress_enabled=ingress_enabled,
            proxy_headers=proxy_headers,
            tls_secret=tls_secret,
            truststores=truststores,
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"keycloak_cluster_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure Keycloak Cluster {cluster_name} in namespace {namespace}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def certificate_present(
    name,
    namespace,
    certificate_name,
    common_name,
    email_address,
    dns_name=None,
    duration="2160h",
    renew_before="360h",
    issuer_ref="self-signed",
):
    """
    Ensure that a Cert-Manager Certificate resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.
    Also checks if the associated Secret resource exists.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace for the Certificate.

    certificate_name
        The name of the Certificate resource in Kubernetes.

    common_name
        The Common Name (CN) for the certificate.

    email_address
        The email address for the certificate subject.

    dns_name
        Optional. DNS name for the certificate. Defaults to None.

    duration
        Optional. Duration of the certificate validity. Defaults to "2160h" (90 days).

    renew_before
        Optional. Time before expiration to renew the certificate. Defaults to "360h" (15 days).

    issuer_ref
        Optional. Reference to the issuer for this certificate. Can be a string (name only), or a dict/list with 'name' and 'kind'. Defaults to "self-signed".

    Example:
    .. code-block:: yaml

        ensure_certificate:
          k8s.certificate_present:
            - namespace: my-namespace
            - certificate_name: my-cert
            - common_name: example.com
            - email_address: admin@example.com
            - dns_name: www.example.com
            - duration: 2160h
            - renew_before: 360h
            - issuer_ref:
              - name: letsencrypt-stage
              - kind: ClusterIssuer
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.certificate_present"](
            namespace=namespace,
            certificate_name=certificate_name,
            common_name=common_name,
            email_address=email_address,
            dns_name=dns_name,
            duration=duration,
            renew_before=renew_before,
            issuer_ref=issuer_ref,
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {
                "certificate_updated": True,
                "secret_exists": result["secret_exists"],
            }
        else:
            ret["changes"] = {
                "secret_exists": result["secret_exists"]
            }  # Report secret status even if no update was needed

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure Certificate {certificate_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def pvc_present(
    name,
    pvc_name,
    namespace,
    storage_class,
    storage_size,
    access_modes=None,
    selector=None,
):
    """
    Ensure a PersistentVolumeClaim (PVC) exists in the specified Kubernetes namespace.

    name
        The name of the state (arbitrary, for SaltStack identification).

    pvc_name
        The name of the PVC to create or update.

    namespace
        The Kubernetes namespace for the PVC.

    storage_class
        The storage class name to use for the PVC.

    storage_size
        The storage capacity to request (e.g., '5Gi', '10Gi').

    access_modes
        Optional. List of access modes (e.g., ['ReadWriteOnce']). Defaults to ['ReadWriteOnce'].

    selector
        Optional. Label selector to match a specific PV (e.g., {'matchLabels': {'type': 'local'}}). Defaults to None.

    Example:
    .. code-block:: yaml

        ensure_ldap_pvc:
          k8s.pvc_present:
            - pvc_name: ldap-pvc
            - namespace: ldap
            - storage_class: local-storage
            - storage_size: 5Gi
            - access_modes:
              - ReadWriteOnce
            - selector:
                matchLabels:
                  type: local-storage
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.pvc_present"](
            name=pvc_name,
            namespace=namespace,
            storage_class=storage_class,
            storage_size=storage_size,
            access_modes=access_modes,
            selector=selector,
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"pvc_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure PVC {pvc_name} in namespace {namespace}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def job_cleanup(name, namespace=None):
    """
    Clean up completed jobs (such as pods) in the specified Kubernetes namespace (or all namespaces if none provided)
    that have a status.phase of Succeeded.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        Optional. The Kubernetes namespace to target. If not provided, targets all namespaces.

    Example:
    .. code-block:: yaml

        cleanup_completed_jobs:
          k8s.job_cleanup:
            - namespace: openstack
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.job_cleanup"](namespace=namespace)

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["deleted_items"]:
            ret["changes"] = {"deleted_items": result["deleted_items"]}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to cleanup completed jobs: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def ceph_object_store_present(
    name,
    namespace,
    replicas=1,
    port=80,
    ssl_enabled=False,
    annotations=None,
    gateway_instances=1,
    gateway_resources=None,
    enable_swift_api=True,
    swift_port=8080,
    swift_account_in_url=True,
    swift_url_prefix="swift",
    enable_s3_api=True,
    preserve_pools_on_delete=True,
    auth_keystone=False,
    keystone_url="",
    keystone_accepted_roles=None,
    keystone_implicit_tenants="swift",
    keystone_revocation_interval=1200,
    keystone_service_user_secret_name="usersecret",
    keystone_token_cache_size=1000,
    rgw_keystone_api_version="3",
    rgw_keystone_implicit_tenants="true",
    rgw_s3_auth_use_keystone="true",
    debug_rgw="0",
):
    """
    Ensure a Ceph Object Store (RGW - RADOS Gateway) exists in the specified Kubernetes namespace using Rook.

    name
        The name of the state (arbitrary, for SaltStack identification) and the Ceph Object Store resource.

    namespace
        The Kubernetes namespace for the Ceph Object Store (typically the Rook namespace).

    replicas
        Optional. Number of RGW replicas for high availability. Defaults to 1.

    port
        Optional. Port for the RGW service (S3 API). Defaults to 80.

    ssl_enabled
        Optional. Enable SSL for RGW service. Defaults to False.

    annotations
        Optional. Additional annotations for the Ceph Object Store resource. Defaults to None.

    gateway_instances
        Optional. Number of gateway instances. Defaults to 1.

    gateway_resources
        Optional. Resource limits and requests for gateway pods as a dictionary. Defaults to None.

    enable_swift_api
        Optional. Enable Swift API compatibility for the object store. Defaults to True.

    swift_port
        Optional. Port for Swift API if enabled. Defaults to 8080.

    swift_account_in_url
        Optional. Include account in Swift URL structure. Defaults to True.

    swift_url_prefix
        Optional. URL prefix for Swift API. Defaults to "swift".

    enable_s3_api
        Optional. Enable S3 API compatibility (default in RGW). Defaults to True.

    preserve_pools_on_delete
        Optional. Preserve metadata and data pools when deleting the object store. Defaults to True.

    auth_keystone
        Optional. Enable Keystone authentication integration. Defaults to False.

    keystone_url
        Optional. URL for Keystone authentication service. Defaults to "".

    keystone_accepted_roles
        Optional. List of roles accepted by Keystone for access. Defaults to None (uses ["admin", "member", "service"] if auth_keystone is True).

    keystone_implicit_tenants
        Optional. Implicit tenant handling for Keystone (e.g., "swift"). Defaults to "swift".

    keystone_revocation_interval
        Optional. Token revocation check interval in seconds. Defaults to 1200.

    keystone_service_user_secret_name
        Mandatory if auth_keystone is True. Name of the secret containing Keystone service user credentials. Defaults to "usersecret".

    rgw_keystone_api_version
        Optional. Keystone API version for RGW authentication. Defaults to "3".

    rgw_keystone_implicit_tenants
        Optional. Enable implicit tenants for Keystone-Swift integration. Defaults to "true".

    rgw_s3_auth_use_keystone
        Optional. Use Keystone for S3 authentication. Defaults to "true".

    debug_rgw
        Optional. Debug level for RGW (e.g., "15" for detailed logging). Defaults to "0" (no debugging).

    rgw_keystone_implicit_tenants
        Optional. Enable implicit tenants for Keystone-Swift integration. Defaults to "true".

    rgw_s3_auth_use_keystone
        Optional. Use Keystone for S3 authentication. Defaults to "true".

    rgw_keystone_api_version
        Optional. Keystone API version for RGW authentication. Defaults to "3".

    keystone_token_cache_size
        Optional. Size of token cache for Keystone authentication. Defaults to 1000.

    Example:
    .. code-block:: yaml

        ensure_ceph_object_store:
          k8s.ceph_object_store_present:
            - name: my-object-store
            - namespace: rook-ceph
            - replicas: 3
            - port: 80
            - ssl_enabled: false
            - gateway_instances: 2
            - enable_swift_api: true
            - swift_port: 8080
            - swift_account_in_url: true
            - swift_url_prefix: "swift"
            - enable_s3_api: true
            - preserve_pools_on_delete: true
            - auth_keystone: true
            - keystone_url: "https://keystone.rook-ceph.svc/"
            - keystone_accepted_roles:
                - admin
                - member
                - service
            - keystone_implicit_tenants: "swift"
            - keystone_revocation_interval: 1200
            - keystone_service_user_secret_name: "usersecret"
            - keystone_token_cache_size: 1000
            - rgw_keystone_api_version: "3"
            - rgw_keystone_implicit_tenants: "true"
            - rgw_s3_auth_use_keystone: "true"
            - debug_rgw: "15"
            - gateway_resources:
                limits:
                  cpu: "500m"
                  memory: "512Mi"
                requests:
                  cpu: "200m"
                  memory: "256Mi"
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic_k8s.ceph_object_store_present"](
            name=name,
            namespace=namespace,
            replicas=replicas,
            port=port,
            ssl_enabled=ssl_enabled,
            annotations=annotations,
            gateway_instances=gateway_instances,
            gateway_resources=gateway_resources,
            enable_swift_api=enable_swift_api,
            swift_port=swift_port,
            swift_account_in_url=swift_account_in_url,
            swift_url_prefix=swift_url_prefix,
            enable_s3_api=enable_s3_api,
            preserve_pools_on_delete=preserve_pools_on_delete,
            auth_keystone=auth_keystone,
            keystone_url=keystone_url,
            keystone_accepted_roles=keystone_accepted_roles,
            keystone_implicit_tenants=keystone_implicit_tenants,
            keystone_revocation_interval=keystone_revocation_interval,
            keystone_service_user_secret_name=keystone_service_user_secret_name,
            keystone_token_cache_size=keystone_token_cache_size,
            rgw_keystone_api_version=rgw_keystone_api_version,
            rgw_keystone_implicit_tenants=rgw_keystone_implicit_tenants,
            rgw_s3_auth_use_keystone=rgw_s3_auth_use_keystone,
            debug_rgw=debug_rgw,
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"ceph_object_store_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure CephObjectStore {name} in namespace {namespace}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def kubernetes_deployment_present(
    name,
    namespace,
    replicas=1,
    image="",
    containers=None,
    labels=None,
    annotations=None,
    resources=None,
    node_selector=None,
    tolerations=None,
    affinity=None,
    service_account_name="",
    init_containers=None,
    volumes=None,
    restart_policy="Always",
):
    """
    Ensure a Kubernetes Deployment is present with the specified configuration.

    Args:
        name (str): Name of the Deployment.
        namespace (str): Namespace in which to create the Deployment.
        replicas (int): Number of pod replicas (default: 1).
        image (str): Container image to use if containers list is not provided (default: "").
        containers (list): List of container specifications.
        labels (dict): Labels for the Deployment.
        annotations (dict): Annotations for the Deployment.
        resources (dict): Resource requirements for containers.
        node_selector (dict): Node selector for pod scheduling.
        tolerations (list): Tolerations for pod scheduling.
        affinity (dict): Affinity rules for pod scheduling (default: None).
        service_account_name (str): Service account to use for pods (default: "").
        init_containers (list): List of init container specifications.
        volumes (list): List of volume specifications.
        restart_policy (str): Restart policy for pods (default: 'Always').

    Returns:
        dict: Result of the operation.
    """
    ret = {"name": name, "result": True, "changes": {}, "comment": ""}

    result = __salt__["kinetic_k8s.kubernetes_deployment_present"](
        name=name,
        namespace=namespace,
        replicas=replicas,
        image=image,
        containers=containers,
        labels=labels,
        annotations=annotations,
        resources=resources,
        node_selector=node_selector,
        tolerations=tolerations,
        affinity=affinity,
        service_account_name=service_account_name,
        init_containers=init_containers,
        volumes=volumes,
        restart_policy=restart_policy,
    )

    if result.get("changes"):
        ret["changes"] = result["changes"]
    if result.get("comment"):
        ret["comment"] = result["comment"]
    ret["result"] = result.get("result", True)

    return ret


def job_present(
    name,
    namespace,
    image,
    command=None,
    args=None,
    service_account=None,
    restart_policy="OnFailure",
    backoff_limit=1,
    ttl_seconds_after_finished=300,
    labels=None,
    annotations=None,
    env=None,
    volumes=None,
    volume_mounts=None,
    resources=None,
    spec=None,
):
    """
    Ensure a Kubernetes Job exists.
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.job_present"](
            namespace=namespace,
            name=name,
            image=image,
            command=command,
            args=args,
            service_account=service_account,
            restart_policy=restart_policy,
            backoff_limit=backoff_limit,
            ttl_seconds_after_finished=ttl_seconds_after_finished,
            labels=labels,
            annotations=annotations,
            env=env,
            volumes=volumes,
            volume_mounts=volume_mounts,
            resources=resources,
            spec=spec,
        )
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"created": True} if result.get("updated", False) else {}
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure Job {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def networkattachmentdefinition_present(
    name,
    namespace="default",
    cni_type="macvlan",
    master="eth0",
    mode="bridge",
    cidr=None,
    range_start=None,
    range_end=None,
    gateway=None,
    ipam_type="whereabouts",
):
    """
    Ensure a Multus NetworkAttachmentDefinition (NAD) exists with the specified IPAM configuration.

    This state creates or updates a NetworkAttachmentDefinition CRD for use with the Multus CNI plugin.

    name
        Name of the NetworkAttachmentDefinition (e.g. 'sfe', 'sbe').

    namespace
        Kubernetes namespace. Defaults to 'default'.

    cidr
        IPAM CIDR range (required).

    range_start, range_end
        IP range boundaries for the IPAM allocator.

    gateway
        Optional gateway. If None, no gateway is configured (as requested).

    Example:
    .. code-block:: yaml

        sfe_network:
          k8s.networkattachmentdefinition_present:
            - name: sfe
            - cidr: 10.150.2.0/24
            - range_start: 10.150.2.10
            - range_end: 10.150.2.254
            # gateway is intentionally omitted (no gateway)

        sbe_network:
          k8s.networkattachmentdefinition_present:
            - name: sbe
            - cidr: 10.150.3.0/24
            - range_start: 10.150.3.10
            - range_end: 10.150.3.254
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.networkattachmentdefinition_present"](
            name=name,
            namespace=namespace,
            cni_type=cni_type,
            master=master,
            mode=mode,
            cidr=cidr,
            range_start=range_start,
            range_end=range_end,
            gateway=gateway,
            ipam_type=ipam_type,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"created": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure NetworkAttachmentDefinition {name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def gateway_present(
    name,
    namespace,
    gateway_class_name,
    listeners=None,
    addresses=None,
    allowed_listeners=None,
    spec=None,
):
    """
    Ensure a Gateway (from Gateway API) is present.

    Important behavior:
      If only `allowed_listeners` is provided (and no `listeners`), listeners on
      ports **80 (HTTP)** and **443 (HTTPS)** are automatically added by the
      execution module. This is required by most Gateway controllers.

    See kinetic_k8s.gateway_present for full details.

    Example (parent/reference gateway):
    .. code-block:: yaml

        internal_gateway:
          k8s.gateway_present:
            - name: internal-gateway
            - namespace: default
            - gateway_class_name: my-gateway-class
            - allowed_listeners:
                namespaces:
                  from: Same
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.gateway_present"](
            namespace=namespace,
            name=name,
            gateway_class_name=gateway_class_name,
            listeners=listeners,
            addresses=addresses,
            allowed_listeners=allowed_listeners,
            spec=spec,
        )
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"created": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure Gateway {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def httproute_present(
    name,
    namespace,
    parent_refs=None,
    rules=None,
    hostname=None,
    hostnames=None,
    spec=None,
):
    """
    Ensure an HTTPRoute (from Gateway API) is present.
rules
    List of HTTPRoute rules (matches, backendRefs, filters).

hostname
    Single hostname for the route (will be converted to hostnames list).

hostnames
    List of hostnames for the route.

spec
    Full spec if provided (hostnames will be merged if provided).

Example:
.. code-block:: yaml

    myroute:
      k8s.httproute_present:
        - name: my-route
        - namespace: default
        - parent_refs:
          - name: my-gateway
            sectionName: http
        - rules:
          - matches:
            - path:
                type: PathPrefix
                value: /
            backendRefs:
            - name: my-service
              port: 80

    # with hostname
    myroute:
      k8s.httproute_present:
        - name: my-route
        - namespace: default
        - spec:
            parentRefs:
              - name: my-gateway
                sectionName: http
            rules:
              - matches:
                - path:
                    type: PathPrefix
                    value: /
                backendRefs:
                - name: my-service
                  port: 80
        - hostname: docs.int.rsc.gacyberrange.org
"""
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.httproute_present"](
            namespace=namespace,
            name=name,
            parent_refs=parent_refs,
            rules=rules,
            hostname=hostname,
            hostnames=hostnames,
            spec=spec,
        )
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"created": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure HTTPRoute {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def backendtlspolicy_present(
    name,
    namespace,
    target_refs=None,
    hostname=None,
    ca_certificate_refs=None,
    well_known_ca_certificates=None,
    validation=None,
    spec=None,
    version="v1",
):
    """
    Ensure a BackendTLSPolicy (from Gateway API) is present.

    BackendTLSPolicy configures TLS from the Gateway/proxy to a backend
    Service (verifying the backend's certificate), similar in purpose to
    the 'backend protocol: HTTPS' style annotations used with Ingress.

    name
        The name of the BackendTLSPolicy.

    namespace
        The namespace for the BackendTLSPolicy.

    target_refs
        List of targetRefs (which Services this policy applies to). Each
        entry supports: group (default ""), kind (default "Service"), name,
        sectionName (optional, matches a named port on the Service).

    hostname
        SNI hostname used to validate the backend's certificate. Merged
        into validation.hostname unless validation already sets it.

    ca_certificate_refs
        List of refs to CA certificate ConfigMaps/Secrets used to validate
        the backend certificate. Merged into validation.caCertificateRefs
        unless validation already sets it.

    well_known_ca_certificates
        Set to "System" to trust the system CA bundle instead of
        ca_certificate_refs. Merged into validation.wellKnownCACertificates
        unless validation already sets it.

    validation
        Full validation dict. Built-from-kwargs values (hostname,
        ca_certificate_refs, well_known_ca_certificates) are merged in for
        any keys not already present.

    spec
        Full spec dict; overrides target_refs/validation/hostname/
        ca_certificate_refs/well_known_ca_certificates entirely if provided.

    version
        Gateway API version for this CRD (default: v1, the stable/GA version
        as of Gateway API 1.3+; use v1alpha3 or v1alpha2 for older Gateway
        API installations where BackendTLSPolicy is still experimental).

    Example:
    .. code-block:: yaml

        efk_backend_tls:
          k8s.backendtlspolicy_present:
            - name: efk-backend-tls
            - namespace: efk
            - target_refs:
              - kind: Service
                name: opensearch-cluster-master
            - hostname: api.logger.services.gacyberrange.org
            - ca_certificate_refs:
              - kind: Secret
                name: opensearch-tls-secret

        # using the system trust store instead of a CA ConfigMap
        opensearch_backend_tls_system_ca:
          k8s.backendtlspolicy_present:
            - name: opensearch-backend-tls
            - namespace: efk
            - target_refs:
              - kind: Service
                name: opensearch-cluster-master
            - hostname: opensearch-cluster-master.efk.svc.cluster.local
            - well_known_ca_certificates: System
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.backendtlspolicy_present"](
            namespace=namespace,
            name=name,
            target_refs=target_refs,
            hostname=hostname,
            ca_certificate_refs=ca_certificate_refs,
            well_known_ca_certificates=well_known_ca_certificates,
            validation=validation,
            spec=spec,
            version=version,
        )
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"created": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure BackendTLSPolicy {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def gatewayclass_present(
    name,
    spec=None,
):
    """
    Ensure a cluster-scoped GatewayClass (from Gateway API) is present.

    See kinetic_k8s.gatewayclass_present for parameter details.

    Example:
    .. code-block:: yaml

        mygatewayclass:
          k8s.gatewayclass_present:
            - name: my-gateway-class
            - spec:
                controllerName: gateway.kgateway.dev/kgateway
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.gatewayclass_present"](
            name=name,
            spec=spec,
        )
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"created": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure GatewayClass {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def serviceaccount_present(name, namespace, labels=None, annotations=None):
    """
    Ensure a Kubernetes ServiceAccount exists in the specified namespace.

    name
        The name of the ServiceAccount.

    namespace
        The namespace for the ServiceAccount.

    labels, annotations
        Optional metadata to apply.

    Example:
    .. code-block:: yaml

        rook_vault_sa:
          k8s.serviceaccount_present:
            - name: rook-vault-auth
            - namespace: rook-ceph
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.serviceaccount_present"](
            namespace=namespace,
            name=name,
            labels=labels,
            annotations=annotations,
        )
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"created": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure ServiceAccount {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def clusterrolebinding_present(name, cluster_role, service_accounts):
    """
    Ensure a Kubernetes ClusterRoleBinding exists binding a ClusterRole to ServiceAccounts.

    name
        The name of the ClusterRoleBinding.

    cluster_role
        The ClusterRole to bind (e.g. 'system:auth-delegator').

    service_accounts
        List of "namespace:serviceaccount" strings.

    Example:
    .. code-block:: yaml

        vault_tokenreview_binding:
          k8s.clusterrolebinding_present:
            - name: vault-tokenreview-binding
            - cluster_role: system:auth-delegator
            - service_accounts:
              - rook-ceph:rook-vault-auth
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.clusterrolebinding_present"](
            name=name,
            cluster_role=cluster_role,
            service_accounts=service_accounts,
        )
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"updated": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure ClusterRoleBinding {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def role_present(name, namespace, rules):
    """
    Ensure a namespaced Kubernetes Role exists with the given rules.

    name
        The name of the Role.

    namespace
        The namespace for the Role.

    rules
        List of rule dicts, e.g.
        [{"api_groups": [""], "resources": ["pods"], "verbs": ["get", "list"]}]

    Example:
    .. code-block:: yaml

        pod_reader_role:
          k8s.role_present:
            - name: pod-reader
            - namespace: default
            - rules:
              - api_groups: [""]
                resources: ["pods"]
                verbs: ["get", "list", "watch"]
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.role_present"](
            namespace=namespace,
            name=name,
            rules=rules,
        )
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"updated": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure Role {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def role_absent(name, namespace):
    """
    Ensure a namespaced Kubernetes Role does not exist.

    name
        The name of the Role.

    namespace
        The namespace of the Role.

    Example:
    .. code-block:: yaml

        pod_reader_role_absent:
          k8s.role_absent:
            - name: pod-reader
            - namespace: default
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.role_absent"](
            namespace=namespace,
            name=name,
        )
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"deleted": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to remove Role {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def clusterrole_present(name, rules):
    """
    Ensure a Kubernetes ClusterRole exists with the given rules.

    name
        The name of the ClusterRole.

    rules
        List of rule dicts, e.g.
        [{"api_groups": [""], "resources": ["pods"], "verbs": ["get", "list"]}]

    Example:
    .. code-block:: yaml

        pod_reader_clusterrole:
          k8s.clusterrole_present:
            - name: pod-reader
            - rules:
              - api_groups: [""]
                resources: ["pods"]
                verbs: ["get", "list", "watch"]
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.clusterrole_present"](
            name=name,
            rules=rules,
        )
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"updated": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure ClusterRole {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def clusterrole_absent(name):
    """
    Ensure a Kubernetes ClusterRole does not exist.

    name
        The name of the ClusterRole.

    Example:
    .. code-block:: yaml

        pod_reader_clusterrole_absent:
          k8s.clusterrole_absent:
            - name: pod-reader
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.clusterrole_absent"](name=name)
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"deleted": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to remove ClusterRole {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def rolebinding_present(
    name,
    namespace,
    role_ref,
    role_ref_kind="Role",
    groups=None,
    users=None,
    service_accounts=None,
    subjects=None,
):
    """
    Ensure a namespaced Kubernetes RoleBinding exists.

    name
        The name of the RoleBinding.

    namespace
        The namespace for the RoleBinding.

    role_ref
        Name of the Role or ClusterRole to bind.

    role_ref_kind
        'Role' or 'ClusterRole'. Defaults to 'Role'.

    groups
        Group names to bind (e.g. from an OIDC "groups" claim sourced from
        an LDAP group, surfaced via Keycloak). Bound as kind=Group.

    users
        Usernames to bind. Bound as kind=User.

    service_accounts
        List of "namespace:serviceaccount" strings, or bare names (defaulting
        to this RoleBinding's namespace).

    subjects
        Raw list of subject dicts for full control, e.g.
        [{"kind": "Group", "name": "k8s-admins"}]. Merged with the
        convenience arguments above.

    Example:
    .. code-block:: yaml

        admins_binding:
          k8s.rolebinding_present:
            - name: admins-binding
            - namespace: default
            - role_ref: admin
            - role_ref_kind: ClusterRole
            - groups:
              - k8s-admins
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.rolebinding_present"](
            namespace=namespace,
            name=name,
            role_ref=role_ref,
            role_ref_kind=role_ref_kind,
            groups=groups,
            users=users,
            service_accounts=service_accounts,
            subjects=subjects,
        )
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"updated": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure RoleBinding {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def rolebinding_absent(name, namespace):
    """
    Ensure a namespaced Kubernetes RoleBinding does not exist.

    name
        The name of the RoleBinding.

    namespace
        The namespace of the RoleBinding.

    Example:
    .. code-block:: yaml

        admins_binding_absent:
          k8s.rolebinding_absent:
            - name: admins-binding
            - namespace: default
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.rolebinding_absent"](
            namespace=namespace,
            name=name,
        )
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"deleted": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to remove RoleBinding {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def clusterrolebinding_group_present(
    name,
    cluster_role,
    groups=None,
    users=None,
    service_accounts=None,
    subjects=None,
):
    """
    Ensure a Kubernetes ClusterRoleBinding exists binding a ClusterRole to
    arbitrary subjects (Groups, Users, and/or ServiceAccounts).

    This is a more general counterpart to k8s.clusterrolebinding_present
    (which is narrowly scoped to ServiceAccount subjects only). Use this
    state for bindings driven by OIDC/LDAP Group subjects.

    name
        The name of the ClusterRoleBinding.

    cluster_role
        The ClusterRole to bind.

    groups
        Group names to bind (e.g. from an OIDC "groups" claim sourced from
        an LDAP group, surfaced via Keycloak). Bound as kind=Group.

    users
        Usernames to bind. Bound as kind=User.

    service_accounts
        List of "namespace:serviceaccount" strings.

    subjects
        Raw list of subject dicts for full control.

    Example:
    .. code-block:: yaml

        k8s_admins_binding:
          k8s.clusterrolebinding_group_present:
            - name: k8s-admins-binding
            - cluster_role: cluster-admin
            - groups:
              - k8s-admins
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.clusterrolebinding_group_present"](
            name=name,
            cluster_role=cluster_role,
            groups=groups,
            users=users,
            service_accounts=service_accounts,
            subjects=subjects,
        )
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"updated": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure ClusterRoleBinding {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def clusterrolebinding_group_absent(name):
    """
    Ensure a Kubernetes ClusterRoleBinding does not exist.

    name
        The name of the ClusterRoleBinding.

    Example:
    .. code-block:: yaml

        k8s_admins_binding_absent:
          k8s.clusterrolebinding_group_absent:
            - name: k8s-admins-binding
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.clusterrolebinding_group_absent"](name=name)
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"deleted": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to remove ClusterRoleBinding {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def serviceaccount_token_secret_present(name, namespace, service_account):
    """
    Ensure a long-lived ServiceAccount token Secret exists (Kubernetes 1.24+).

    Create-only: Kubernetes populates the token/ca.crt data automatically,
    so this state never updates an existing Secret.

    name
        The name of the Secret.

    namespace
        The namespace for the Secret.

    service_account
        The ServiceAccount name to annotate the Secret with.

    Example:
    .. code-block:: yaml

        rook_vault_sa_token:
          k8s.serviceaccount_token_secret_present:
            - name: rook-vault-auth-token
            - namespace: rook-ceph
            - service_account: rook-vault-auth
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_k8s.serviceaccount_token_secret_present"](
            namespace=namespace,
            name=name,
            service_account=service_account,
        )
        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"created": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure ServiceAccount token Secret {name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret
