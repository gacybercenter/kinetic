# -*- coding: utf-8 -*-
"""
SaltStack state module for managing Kubernetes resources using the kinetic-k8s execution module.

This module provides states for managing Bare Metal Hosts (BMH), Secrets for network data, userdata,
BMC authentication, and UUIDs, as well as querying hardware data from Kubernetes Custom Resources.
"""

from salt.exceptions import SaltInvocationError

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
def mariadb_instance_present(name, namespace, instance_name, root_password, secret_name="mariadb-root-password", image="mariadb:10.6", storage_size="1Gi", storage_class="standard", pvc_name=None, replicas=1, limits_cpu="500m", limits_memory="512Mi", requests_cpu="200m", requests_memory="256Mi"):
    """
    Ensure that a MariaDB instance is present in Kubernetes using the MariaDB Operator.
    Creates or updates a root password Secret and the MariaDB instance Custom Resource with specified storage class, size, and optional PVC name.
    Checks if the associated PVC is available.

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
            - storage_class: gp2
            - pvc_name: my-custom-pvc
            - replicas: 1
            - limits_cpu: 500m
            - limits_memory: 512Mi
            - requests_cpu: 200m
            - requests_memory: 256Mi
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
            requests_memory=requests_memory
        )

        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['updated'] or result['secret_updated']:
            ret['changes'] = {
                'instance_updated': result['updated'],
                'secret_updated': result['secret_updated'],
                'pvc_available': result['pvc_available']
            }
        else:
            ret['changes'] = {}  # Explicitly empty to prevent SaltStack from reporting changes

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure MariaDB instance {instance_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret