# -*- coding: utf-8 -*-
"""
SaltStack state module for managing Kubernetes resources using the kinetic-k8s execution module.

This module provides states for managing Bare Metal Hosts (BMH), Secrets for network data, userdata,
BMC authentication, and UUIDs, as well as querying hardware data from Kubernetes Custom Resources.
"""

from salt.exceptions import SaltInvocationError
from kubernetes import client, config
from kubernetes.client.rest import ApiException
import base64
__virtualname__ = 'k8s'

def __virtual__():
    """
    Check if the kinetic-k8s execution module is available.
    """
    if 'kinetic-k8s.get_mac_by_interface_name' in __salt__:
        return __virtualname__
    return (False, 'The kinetic-k8s execution module is not available.')

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
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        result = __salt__['kinetic-k8s.get_mac_by_interface_name'](namespace, resource_name, interface_name)
        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['success']:
            ret['changes'] = {'mac': result['mac']}
        else:
            ret['changes'] = {}
    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to retrieve MAC address: {str(e)[:100]}..."
        ret['changes'] = {}

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
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        result = __salt__['kinetic-k8s.get_all_interfaces'](namespace, resource_name)
        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['success']:
            ret['changes'] = {'interfaces': result['interfaces']}
        else:
            ret['changes'] = {}
    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to retrieve interfaces: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret

def bmh_present(name, namespace, bmh_name, pillar_data=None, pillar_key="bmh", bmh_template_path='salt://formulas/bmo/files/bmh.j2'):
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
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        # If pillar_data is not provided, fetch it using pillar_key and bmh_name
        if pillar_data is None:
            if pillar_key is None:
                raise SaltInvocationError('Either pillar_data or pillar_key must be provided.')
            # Fetch the full BMH pillar data and extract the specific host entry
            full_pillar_data = __salt__['pillar.get'](pillar_key, {})
            debug_pillar_msg = f"Pillar data fetched for key '{pillar_key}': type={type(full_pillar_data).__name__}; "
            if isinstance(full_pillar_data, dict):
                debug_pillar_msg += f"keys={list(full_pillar_data.keys())[:5]}; "
                if 'bmh' in full_pillar_data and isinstance(full_pillar_data['bmh'], dict):
                    debug_pillar_msg += f"bmh keys={list(full_pillar_data['bmh'].keys())[:5]}; "
                    pillar_data = full_pillar_data['bmh'].get(bmh_name, {})
                elif full_pillar_data.get(bmh_name) and isinstance(full_pillar_data.get(bmh_name), dict):
                    pillar_data = full_pillar_data.get(bmh_name, {})
                    debug_pillar_msg += f"direct host data for {bmh_name} found; "
                else:
                    pillar_data = {}
                    debug_pillar_msg += f"no data for {bmh_name} found; "
            else:
                pillar_data = {}
                debug_pillar_msg += f"value preview={repr(full_pillar_data)[:50]}...; "
        else:
            debug_pillar_msg = "Pillar data provided directly; "

        # Call the execution module function
        result = __salt__['kinetic-k8s.bmh_present'](namespace, bmh_name, pillar_data, bmh_template_path)

        ret['result'] = result['success']
        ret['comment'] = result['message']
        ret['comment'] += f" Debug: {debug_pillar_msg}"
        if result['updated']:
            ret['changes'] = {
                'bmh_updated': True,
                'recreated': result['recreated']
            }
        else:
            ret['changes'] = {}  # Explicitly empty to prevent SaltStack from reporting changes

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure BMH {bmh_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret

def networkdata_present(name, namespace, bmh_name, defaults, pillar_data=None, pillar_key="bmh", network_template_path='salt://formulas/bmo/files/network-data.j2'):
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
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        # If pillar_data is not provided, fetch it using pillar_key and bmh_name
        if pillar_data is None:
            if pillar_key is None:
                raise SaltInvocationError('Either pillar_data or pillar_key must be provided.')
            # Fetch the full BMH pillar data and extract the specific host entry
            full_pillar_data = __salt__['pillar.get'](pillar_key, {})
            debug_pillar_msg = f"Pillar data fetched for key '{pillar_key}': type={type(full_pillar_data).__name__}; "
            if isinstance(full_pillar_data, dict):
                debug_pillar_msg += f"keys={list(full_pillar_data.keys())[:5]}; "
                if 'bmh' in full_pillar_data and isinstance(full_pillar_data['bmh'], dict):
                    debug_pillar_msg += f"bmh keys={list(full_pillar_data['bmh'].keys())[:5]}; "
                    pillar_data = full_pillar_data['bmh'].get(bmh_name, {})
                elif full_pillar_data.get(bmh_name) and isinstance(full_pillar_data.get(bmh_name), dict):
                    pillar_data = full_pillar_data.get(bmh_name, {})
                    debug_pillar_msg += f"direct host data for {bmh_name} found; "
                else:
                    pillar_data = {}
                    debug_pillar_msg += f"no data for {bmh_name} found; "
            else:
                pillar_data = {}
                debug_pillar_msg += f"value preview={repr(full_pillar_data)[:50]}...; "
        else:
            debug_pillar_msg = "Pillar data provided directly; "

        # Call the execution module function
        result = __salt__['kinetic-k8s.networkdata_present'](namespace, bmh_name, defaults, pillar_data, network_template_path)

        ret['result'] = result['success']
        ret['comment'] = result['message']
        ret['comment'] += f" Debug: {debug_pillar_msg}"
        if result['updated']:
            ret['changes'] = {'networkdata_updated': True}
        else:
            ret['changes'] = {}  # Explicitly empty to prevent SaltStack from reporting changes

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure network data Secret for {bmh_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret

def userdata_present(name, namespace, bmh_name, pillar_data=None, pillar_key="bmh", userdata_template_path='salt://formulas/bmo/files/cloudinit.j2'):
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
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        # If pillar_data is not provided, fetch it using pillar_key and bmh_name
        if pillar_data is None:
            if pillar_key is None:
                raise SaltInvocationError('Either pillar_data or pillar_key must be provided.')
            # Fetch the full BMH pillar data and extract the specific host entry
            full_pillar_data = __salt__['pillar.get'](pillar_key, {})
            debug_pillar_msg = f"Pillar data fetched for key '{pillar_key}': type={type(full_pillar_data).__name__}; "
            if isinstance(full_pillar_data, dict):
                debug_pillar_msg += f"keys={list(full_pillar_data.keys())[:5]}; "
                if 'bmh' in full_pillar_data and isinstance(full_pillar_data['bmh'], dict):
                    debug_pillar_msg += f"bmh keys={list(full_pillar_data['bmh'].keys())[:5]}; "
                    pillar_data = full_pillar_data['bmh'].get(bmh_name, {})
                elif full_pillar_data.get(bmh_name) and isinstance(full_pillar_data.get(bmh_name), dict):
                    pillar_data = full_pillar_data.get(bmh_name, {})
                    debug_pillar_msg += f"direct host data for {bmh_name} found; "
                else:
                    pillar_data = {}
                    debug_pillar_msg += f"no data for {bmh_name} found; "
            else:
                pillar_data = {}
                debug_pillar_msg += f"value preview={repr(full_pillar_data)[:50]}...; "
        else:
            debug_pillar_msg = "Pillar data provided directly; "

        # Call the execution module function
        result = __salt__['kinetic-k8s.userdata_present'](namespace, bmh_name, pillar_data, userdata_template_path)

        ret['result'] = result['success']
        ret['comment'] = result['message']
        ret['comment'] += f" Debug: {debug_pillar_msg}"
        if result['updated']:
            ret['changes'] = {'userdata_updated': True}
        else:
            ret['changes'] = {}  # Explicitly empty to prevent SaltStack from reporting changes

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure userdata Secret for {bmh_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret

def host_bmc_auth_present(name, namespace, bmh_name, ipmi, pillar_data=None, pillar_key="bmh", bmc_auth_template_path='salt://formulas/bmo/files/bmc-auth.j2'):
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
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        # If pillar_data is not provided, fetch it using pillar_key and bmh_name
        if pillar_data is None:
            if pillar_key is None:
                raise SaltInvocationError('Either pillar_data or pillar_key must be provided.')
            # Fetch the full BMH pillar data and extract the specific host entry
            full_pillar_data = __salt__['pillar.get'](pillar_key, {})
            debug_pillar_msg = f"Pillar data fetched for key '{pillar_key}': type={type(full_pillar_data).__name__}; "
            if isinstance(full_pillar_data, dict):
                debug_pillar_msg += f"keys={list(full_pillar_data.keys())[:5]}; "
                if 'bmh' in full_pillar_data and isinstance(full_pillar_data['bmh'], dict):
                    debug_pillar_msg += f"bmh keys={list(full_pillar_data['bmh'].keys())[:5]}; "
                    pillar_data = full_pillar_data['bmh'].get(bmh_name, {})
                elif full_pillar_data.get(bmh_name) and isinstance(full_pillar_data.get(bmh_name), dict):
                    pillar_data = full_pillar_data.get(bmh_name, {})
                    debug_pillar_msg += f"direct host data for {bmh_name} found; "
                else:
                    pillar_data = {}
                    debug_pillar_msg += f"no data for {bmh_name} found; "
            else:
                pillar_data = {}
                debug_pillar_msg += f"value preview={repr(full_pillar_data)[:50]}...; "
        else:
            debug_pillar_msg = "Pillar data provided directly; "

        # Call the execution module function
        result = __salt__['kinetic-k8s.host_bmc_auth_present'](namespace, bmh_name, ipmi, pillar_data, bmc_auth_template_path)

        ret['result'] = result['success']
        ret['comment'] = result['message']
        ret['comment'] += f" Debug: {debug_pillar_msg}"
        if result['updated']:
            ret['changes'] = {'bmc_auth_updated': True}
        else:
            ret['changes'] = {}  # Explicitly empty to prevent SaltStack from reporting changes

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure BMC auth Secret for {bmh_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret

def uuids_present(name, namespace, secret_name, pillar_data=None, pillar_key="bmh", deployment_name="salt-master", wait_timeout=300, wait_interval=10, salt_check_timeout=120, salt_check_interval=5, salt_check_key="bmh"):
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
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        # If pillar_data is not provided, fetch it using pillar_key
        if pillar_data is None:
            if pillar_key is None:
                raise SaltInvocationError('Either pillar_data or pillar_key must be provided.')
            # Fetch the pillar data as a dictionary with the provided key
            pillar_data = __salt__['pillar.get'](pillar_key, {})
            debug_pillar_msg = f"Pillar data fetched for key '{pillar_key}': type={type(pillar_data).__name__}; "
            if isinstance(pillar_data, dict):
                debug_pillar_msg += f"keys={list(pillar_data.keys())[:5]}; "
                if 'bmh' in pillar_data and isinstance(pillar_data['bmh'], dict):
                    debug_pillar_msg += f"bmh keys={list(pillar_data['bmh'].keys())[:5]}; "
                elif pillar_data and any(isinstance(v, dict) and 'uuid' in v for v in pillar_data.values()):
                    debug_pillar_msg += f"direct host data detected in keys; "
            else:
                debug_pillar_msg += f"value preview={repr(pillar_data)[:50]}...; "
            # If the fetched data is not a dictionary, wrap it (unlikely but for safety)
            if not isinstance(pillar_data, dict):
                pillar_data = {pillar_key: pillar_data}

        # Call the execution module function
        result = __salt__['kinetic-k8s.uuids_secret_present'](namespace, secret_name, pillar_data, deployment_name, wait_timeout, wait_interval, salt_check_timeout, salt_check_interval, salt_check_key)

        ret['result'] = result['success']
        ret['comment'] = result['message']
        if pillar_data is not None and debug_pillar_msg:
            ret['comment'] += f" Debug: {debug_pillar_msg}"
        if result['updated']:
            ret['changes'] = {
                'secret_updated': True,
                'deployment_restarted': result['restarted'],
                'deployment_waited': result['waited'],
                'salt_responded': result['salt_responded']
            }
        else:
            ret['changes'] = {}  # Explicitly empty to prevent SaltStack from reporting changes

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure Secret {secret_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret
def mariadb_instance_present(name, namespace, instance_name, root_password, secret_name="mariadb-root-password", image="mariadb:10.6", storage_size="1Gi", storage_class="standard", pvc_name=None, replicas=1, limits_cpu="500m", limits_memory="512Mi", requests_cpu="200m", requests_memory="256Mi", admin_host_access="%"):
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
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        # Call the execution module function
        result = __salt__['kinetic-k8s.mariadb_instance_present'](
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
            admin_host_access=admin_host_access
        )

        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['updated'] or result['secret_updated'] or result['root_access_updated']:
            ret['changes'] = {
                'instance_updated': result['updated'],
                'secret_updated': result['secret_updated'],
                'pvc_available': result['pvc_available'],
                'root_access_updated': result['root_access_updated']
            }
        else:
            ret['changes'] = {}  # Explicitly empty to prevent SaltStack from reporting changes

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure MariaDB instance {instance_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret
def local_storage_pv_pvc_present(name, namespace, pv_name, pvc_name, storage_size="1Gi", node_name=None, path="/mnt/local-storage", storage_class="local-storage"):
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
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        # Call the execution module function
        result = __salt__['kinetic-k8s.local_storage_pv_pvc_present'](namespace, pv_name, pvc_name, storage_size, node_name, path, storage_class)

        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['pv_updated'] or result['pvc_updated']:
            ret['changes'] = {
                'pv_updated': result['pv_updated'],
                'pvc_updated': result['pvc_updated'],
                'bound': result['bound']
            }
        else:
            ret['changes'] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure local storage PV {pv_name} and PVC {pvc_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret
def ironic_db_user_present(name, namespace, mariadb_name, mariadb_namespace, user_name, user_password, secret_name, database_name="ironic-database", host="%", max_user_connections=100, privileges=["ALL PRIVILEGES"], table="*"):
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
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        result = __salt__['kinetic-k8s.ironic_db_user_setup'](
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
            table=table
        )

        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['secret_updated'] or result['user_updated'] or result['grant_updated']:
            ret['changes'] = {
                'secret_updated': result['secret_updated'],
                'user_updated': result['user_updated'],
                'grant_updated': result['grant_updated']
            }
        else:
            ret['changes'] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure Ironic DB user setup for {user_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret
def mariadb_database_present(name, namespace, database_name, mariadb_name, mariadb_namespace, character_set="utf8", collate="utf8_general_ci", cleanup_policy="Delete"):

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
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        result = __salt__['kinetic-k8s.mariadb_database_present'](
            namespace=namespace,
            database_name=database_name,
            mariadb_name=mariadb_name,
            mariadb_namespace=mariadb_namespace,
            character_set=character_set,
            collate=collate,
            cleanup_policy=cleanup_policy
        )

        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['updated']:
            ret['changes'] = {
                'database_updated': True
            }
        else:
            ret['changes'] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure Database {database_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret
def tls_secret_present(name, namespace, secret_name, common_name="ironic-operator", validity_days=365):
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
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        result = __salt__['kinetic-k8s.generate_tls_secret'](
            namespace=namespace,
            secret_name=secret_name,
            common_name=common_name,
            validity_days=validity_days
        )

        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['updated']:
            ret['changes'] = {
                'secret_updated': True
            }
        else:
            ret['changes'] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure TLS Secret {secret_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret
def ironic_operator_present(name, namespace="ironic-standalone-operator-system", deployment_name="ironic-standalone-operator-controller-manager", timeout=60):
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
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        result = __salt__['kinetic-k8s.check_ironic_operator'](namespace, deployment_name, timeout)
        ret['result'] = result['success']
        ret['comment'] = result['message']
        # Only report changes if needed; keep empty for check-only state
        ret['changes'] = {}
        # If the state fails, append a message with the command to run
        if not result['success']:
            ironic_op_dir = __salt__['pillar.get']('ironic_op_dir', '<path-to-ironic-operator-repo>')
            ret['comment'] += f"; If the Ironic Operator is not installed, please run 'make install deploy' in the directory {ironic_op_dir} to install it."
    except Exception as e:
        ret['result'] = False
        ironic_op_dir = __salt__['pillar.get']('ironic_op_dir', '<path-to-ironic-operator-repo>')
        ret['comment'] = f"Failed to check Ironic Operator: {str(e)[:100]}...; If the Ironic Operator is not installed, please run 'make install deploy' in the directory {ironic_op_dir} to install it."
        ret['changes'] = {}

    return ret
def ironic_instance_present(name, namespace, instance_name, database_secret_name="ironic-user", database_host="ironic-mariadb", database_port=3306, database_user="ironic", database_name="ironic", http_port=6385, provisioning_interface="ironic-provisioning", provisioning_nic="eth0", provisioning_dhcp_range_start="", provisioning_dhcp_range_end="", provisioning_dhcp_range_gateway="", provisioning_dhcp_range_netmask="", inspection_dhcp_all_interfaces=False, enable_keepalived=False, keepalived_vip="", keepalived_interface="eth0", tls_secret_name="ironic-tls"):
    """
    Ensure that an Ironic instance is present in Kubernetes using the Ironic Standalone Operator.
    Creates or updates the Ironic Custom Resource with specified database connection, networking, and optional Keepalived settings.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace where the Ironic instance will reside.

    instance_name
        The name of the Ironic instance (Custom Resource).

    database_secret_name
        Optional. The name of the Secret containing database credentials. Defaults to 'ironic-user'.

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

    provisioning_interface
        Optional. The provisioning interface name. Defaults to 'ironic-provisioning'.

    provisioning_nic
        Optional. The NIC for provisioning. Defaults to 'eth0'.

    provisioning_dhcp_range_start
        Optional. Start of DHCP range for provisioning. Defaults to empty (no DHCP).

    provisioning_dhcp_range_end
        Optional. End of DHCP range for provisioning. Defaults to empty (no DHCP).

    provisioning_dhcp_range_gateway
        Optional. Gateway for DHCP range. Defaults to empty.

    provisioning_dhcp_range_netmask
        Optional. Netmask for DHCP range. Defaults to empty.

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

    Example:
    .. code-block:: yaml

        ensure_ironic_instance:
          k8s.ironic_instance_present:
            - namespace: ironic-standalone-operator-system
            - instance_name: ironic
            - database_secret_name: ironic-user
            - database_host: ironic-mariadb
            - database_port: 3306
            - database_user: ironic
            - database_name: ironic
            - http_port: 6385
            - provisioning_interface: ironic-provisioning
            - provisioning_nic: eth0
            - provisioning_dhcp_range_start: 192.168.123.100
            - provisioning_dhcp_range_end: 192.168.123.200
            - provisioning_dhcp_range_gateway: 192.168.123.1
            - provisioning_dhcp_range_netmask: 255.255.255.0
            - inspection_dhcp_all_interfaces: False
            - enable_keepalived: True
            - keepalived_vip: 192.168.123.10
            - keepalived_interface: eth0
            - tls_secret_name: ironic-tls
    """
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        result = __salt__['kinetic-k8s.ironic_instance_present'](
            namespace=namespace,
            instance_name=instance_name,
            database_secret_name=database_secret_name,
            database_host=database_host,
            database_port=database_port,
            database_user=database_user,
            database_name=database_name,
            http_port=http_port,
            provisioning_interface=provisioning_interface,
            provisioning_nic=provisioning_nic,
            provisioning_dhcp_range_start=provisioning_dhcp_range_start,
            provisioning_dhcp_range_end=provisioning_dhcp_range_end,
            provisioning_dhcp_range_gateway=provisioning_dhcp_range_gateway,
            provisioning_dhcp_range_netmask=provisioning_dhcp_range_netmask,
            inspection_dhcp_all_interfaces=inspection_dhcp_all_interfaces,
            enable_keepalived=enable_keepalived,
            keepalived_vip=keepalived_vip,
            keepalived_interface=keepalived_interface,
            tls_secret_name=tls_secret_name
        )

        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['updated']:
            ret['changes'] = {
                'ironic_updated': True
            }
        else:
            ret['changes'] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure Ironic instance {instance_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret