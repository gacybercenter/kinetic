# -*- coding: utf-8 -*-
"""
SaltStack execution module for interacting with Kubernetes to retrieve hardware data.

This module provides functions to query Kubernetes Custom Resources, specifically
for retrieving MAC addresses from HardwareData resources in a Metal3.io environment.
"""

import salt.utils.decorators as decorators
from kubernetes import client, config
from kubernetes.client.rest import ApiException

# Ensure Salt can find this module
__virtualname__ = 'kinetic-k8s'

@decorators.memoize
def __virtual__():
    """
    Check if the kubernetes python library is available.
    """
    try:
        from kubernetes import client
        return __virtualname__
    except ImportError:
        return (False, 'The kubernetes python library is not installed. Please install it using "pip install kubernetes".')

def get_mac_by_interface_name(namespace, resource_name, interface_name):
    """
    Retrieve the MAC address of a network interface from a HardwareData Custom Resource in Kubernetes.

    Args:
        namespace (str): The namespace of the HardwareData resource.
        resource_name (str): The name of the HardwareData resource.
        interface_name (str): The name of the network interface to query.

    Returns:
        dict: A dictionary with 'success' (bool), 'mac' (str if found), and 'message' (str for status or error).

    CLI Example:
        salt '*' kinetic-k8s.get_mac_by_interface_name baremetal-operator-system compute-133-26 enp97s0f0
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        group = "metal3.io"
        version = "v1alpha1"
        plural = "hardwaredata"

        resource = custom_api.get_namespaced_custom_object(
            group=group, version=version, namespace=namespace, plural=plural, name=resource_name
        )

        nics = resource.get('spec', {}).get('hardware', {}).get('nics', [])
        for nic in nics:
            if nic.get('name') == interface_name:
                return {
                    'success': True,
                    'mac': nic.get('mac', ''),
                    'message': f"Found MAC for {interface_name}"
                }

        return {
            'success': False,
            'mac': '',
            'message': f"Interface {interface_name} not found"
        }

    except ApiException as e:
        return {
            'success': False,
            'mac': '',
            'message': f"Kubernetes API error: {str(e)[:50]}..."
        }
    except Exception as e:
        return {
            'success': False,
            'mac': '',
            'message': f"Error: {str(e)[:50]}..."
        }

def get_all_interfaces(namespace, resource_name):
    """
    Retrieve all network interfaces and their MAC addresses from a HardwareData Custom Resource.

    Args:
        namespace (str): The namespace of the HardwareData resource.
        resource_name (str): The name of the HardwareData resource.

    Returns:
        dict: A dictionary with 'success' (bool), 'interfaces' (dict of interface name to MAC), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.get_all_interfaces baremetal-operator-system compute-133-26
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        group = "metal3.io"
        version = "v1alpha1"
        plural = "hardwaredata"

        resource = custom_api.get_namespaced_custom_object(
            group=group, version=version, namespace=namespace, plural=plural, name=resource_name
        )

        nics = resource.get('spec', {}).get('hardware', {}).get('nics', [])
        interfaces = {nic.get('name'): nic.get('mac') for nic in nics if nic.get('name') and nic.get('mac')}

        return {
            'success': True,
            'interfaces': interfaces,
            'message': f"Retrieved {len(interfaces)} interfaces"
        }

    except ApiException as e:
        return {
            'success': False,
            'interfaces': {},
            'message': f"Kubernetes API error: {str(e)[:50]}..."
        }
    except Exception as e:
        return {
            'success': False,
            'interfaces': {},
            'message': f"Error: {str(e)[:50]}..."
        }

def bmh_present(namespace, bmh_name, pillar_data, bmh_template_path='salt://formulas/bmo/files/bmh.j2'):
    """
    Ensure that the Bare Metal Host (BMH) object in Kubernetes matches the desired state
    defined by pillar data and Jinja2 template. Updates BMH if possible, or deletes and recreates
    if it needs updating and is in an error state.

    Args:
        namespace (str): The namespace of the Bare Metal Host resource in Kubernetes.
        bmh_name (str): The name of the Bare Metal Host resource.
        pillar_data (dict): Pillar data containing the desired BMH configuration.
        bmh_template_path (str, optional): Salt URI to the Jinja2 template file for BMH.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'recreated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.bmh_present baremetal-operator-system compute-133-26 pillar_data
    """
    try:
        updated = False
        recreated = False
        exists = False
        matches = False
        in_error_state = False
        differences = {}

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        group = "metal3.io"
        version = "v1alpha1"
        plural = "baremetalhosts"

        # Check if BMH exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=namespace, plural=plural, name=bmh_name
            )
            exists = True
            current_bmh = resource.get('spec', {})
            status = resource.get('status', {})
            in_error_state = status.get('errorMessage', '') != '' or status.get('provisioning', {}).get('state', '') == 'error'
        except ApiException:
            exists = False
            current_bmh = {}
        except Exception as e:
            exists = False
            current_bmh = {}
            return {
                'success': False,
                'updated': False,
                'recreated': False,
                'message': f"Error fetching BMH: {str(e)[:50]}..."
            }

        # Render desired BMH configuration
        try:
            network_data_name = f"{bmh_name}-network-data"
            userdata_name = f"{bmh_name}-user-data"
            bmc_auth_name = f"{bmh_name}-bmc-auth"
            bmh_context = {
                'name': bmh_name, 'namespace': namespace, 'online': pillar_data.get('online', False),
                'address': pillar_data.get('bmc', {}).get('address', ''),
                'credentialsName': bmc_auth_name, 'bootMACAddress': pillar_data.get('bootMACAddress', ''),
                'checksum': pillar_data.get('image', {}).get('checksum', ''),
                'format': pillar_data.get('image', {}).get('format', ''),
                'url': pillar_data.get('image', {}).get('url', ''),
                'rootdevice': pillar_data.get('rootDeviceHints', {}).get('deviceName', ''),
                'networkdata': network_data_name if 'network' in pillar_data else '',
                'userdata': userdata_name if 'network' in pillar_data else ''
            }

            bmh_content = __salt__['cp.get_file_str'](bmh_template_path)
            if not bmh_content:
                raise Exception(f"Empty BMH template at {bmh_template_path}")
            if bmh_content.startswith('#!'):
                bmh_content = '\n'.join(bmh_content.splitlines()[1:]) if len(bmh_content.splitlines()) > 1 else ''
            rendered_bmh = __salt__['slsutil.renderer'](string=bmh_content, default_renderer='jinja|yaml', context=bmh_context)
            if not rendered_bmh:
                raise Exception("Failed to render BMH template")

            import yaml
            desired_bmh = rendered_bmh if isinstance(rendered_bmh, dict) else yaml.safe_load(rendered_bmh)

            if exists:
                current_spec = current_bmh
                desired_spec = desired_bmh.get('spec', {})
                for key in desired_spec:
                    if key not in current_spec or current_spec[key] != desired_spec[key]:
                        differences[key] = {'desired': desired_spec[key]}
                matches = len(differences) == 0
            else:
                matches = False
        except Exception as e:
            return {
                'success': False,
                'updated': False,
                'recreated': False,
                'message': f"BMH template render failed: {str(e)[:50]}..."
            }

        # Update or create BMH only if necessary
        if not exists:
            try:
                custom_api.create_namespaced_custom_object(group=group, version=version, namespace=namespace, plural=plural, body=desired_bmh)
                updated = True
                recreated = True
                message = f"BMH {bmh_name} created"
            except ApiException as e:
                updated = False
                recreated = False
                message = f"BMH {bmh_name} creation failed: {str(e)[:50]}..."
        elif not matches or in_error_state:
            try:
                body = desired_bmh
                if exists and 'metadata' in resource and 'resourceVersion' in resource['metadata']:
                    body.setdefault('metadata', {}).update({'resourceVersion': resource['metadata'].get('resourceVersion', '')})
                try:
                    custom_api.replace_namespaced_custom_object(group=group, version=version, namespace=namespace, plural=plural, name=bmh_name, body=body)
                    updated = True
                    recreated = False
                    message = f"BMH {bmh_name} updated"
                except ApiException as update_error:
                    if in_error_state:
                        import time
                        custom_api.delete_namespaced_custom_object(group=group, version=version, namespace=namespace, plural=plural, name=bmh_name, body=client.V1DeleteOptions(propagation_policy='Foreground', grace_period_seconds=5))
                        wait_time = 0
                        max_wait = 60
                        wait_interval = 5
                        while wait_time < max_wait:
                            try:
                                custom_api.get_namespaced_custom_object(group=group, version=version, namespace=namespace, plural=plural, name=bmh_name)
                                time.sleep(wait_interval)
                                wait_time += wait_interval
                            except ApiException as get_error:
                                if get_error.status == 404:
                                    break
                                else:
                                    message = f"BMH {bmh_name} deletion check failed: {str(get_error)[:50]}..."
                                    break
                        custom_api.create_namespaced_custom_object(group=group, version=version, namespace=namespace, plural=plural, body=body)
                        updated = True
                        recreated = True
                        message = f"BMH {bmh_name} recreated"
                    else:
                        updated = False
                        recreated = False
                        message = f"BMH {bmh_name} update failed: {str(update_error)[:50]}..."
            except ApiException as e:
                updated = False
                recreated = False
                message = f"BMH {bmh_name} operation failed: {str(e)[:50]}..."
        else:
            message = f"BMH {bmh_name} already up-to-date"
            updated = False
            recreated = False

        return {
            'success': True if updated or matches else False,
            'updated': updated,
            'recreated': recreated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'recreated': False,
            'message': f"BMH operation error: {str(e)[:50]}..."
        }

def networkdata_present(namespace, bmh_name, defaults, pillar_data, network_template_path='salt://formulas/bmo/files/network-data.j2'):
    """
    Ensure that the network data Secret in Kubernetes matches the desired state
    defined by pillar data and Jinja2 template.

    Args:
        namespace (str): The namespace of the network data Secret in Kubernetes.
        bmh_name (str): The name of the Bare Metal Host resource (used for Secret naming).
        defaults (dict): Default values for network configuration.
        pillar_data (dict): Pillar data containing the desired network configuration.
        network_template_path (str, optional): Salt URI to the Jinja2 template file for network data.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.networkdata_present baremetal-operator-system compute-133-26 defaults pillar_data
    """
    try:
        updated = False
        exists = False
        matches = False
        current_network = {}
        desired_network = {}
        differences = {}

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()
        network_data_name = f"{bmh_name}-network-data"

        if 'network' in pillar_data:
            try:
                network_secret = core_v1_api.read_namespaced_secret(name=network_data_name, namespace=namespace)
                exists = True
                current_network = network_secret.string_data if network_secret.string_data else {}
                if not current_network and network_secret.data:
                    import base64
                    current_network = {k: base64.b64decode(v).decode('utf-8') for k, v in network_secret.data.items()}
            except ApiException:
                exists = False
                current_network = {}
            except Exception:
                exists = False
                current_network = {}
        else:
            exists = False
            current_network = {}
            message = f"Network data not applicable for {bmh_name}"
            return {
                'success': True,
                'updated': False,
                'message': message
            }

        if 'network' in pillar_data:
            try:
                network_context = {
                    'interface': defaults['interface'], 'mac': defaults['mac'], 'ip': defaults['ip'],
                    'prefix': defaults['prefix'], 'gateway': defaults['gateway'], 'nameserver': defaults['nameserver']
                }
                network_content = __salt__['cp.get_file_str'](network_template_path)
                if not network_content:
                    raise Exception(f"Empty network template at {network_template_path}")
                if network_content.startswith('#!'):
                    network_content = '\n'.join(network_content.splitlines()[1:]) if len(network_content.splitlines()) > 1 else ''
                rendered_network = __salt__['slsutil.renderer'](string=network_content, default_renderer='jinja', context=network_context)
                if not rendered_network:
                    raise Exception("Failed to render network template")

                import json
                desired_network_json = json.loads(rendered_network)
                desired_network = {'networkData': json.dumps(desired_network_json)}

                if exists:
                    current_data = current_network
                    if isinstance(current_network, dict) and 'networkData' in current_network:
                        try:
                            current_data = json.loads(current_network['networkData'])
                        except Exception:
                            current_data = current_network
                    desired_data = json.loads(desired_network['networkData'])
                    for key in desired_data:
                        if key not in current_data or current_data[key] != desired_data[key]:
                            differences[key] = {'desired': desired_data[key]}
                    matches = len(differences) == 0
                else:
                    matches = False
            except Exception as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Network data render failed: {str(e)[:50]}..."
                }
        else:
            desired_network = {}
            matches = False
            message = f"Network data not applicable for {bmh_name}"
            return {
                'success': True,
                'updated': False,
                'message': message
            }

        if 'network' in pillar_data and (not exists or not matches):
            try:
                body = client.V1Secret(metadata=client.V1ObjectMeta(name=network_data_name, namespace=namespace), string_data=desired_network, type='Opaque')
                if exists:
                    core_v1_api.replace_namespaced_secret(name=network_data_name, namespace=namespace, body=body)
                    updated = True
                    message = f"Network Secret {network_data_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(namespace=namespace, body=body)
                    updated = True
                    message = f"Network Secret {network_data_name} created"
            except ApiException as e:
                updated = False
                message = f"Network Secret {network_data_name} operation failed: {str(e)[:50]}..."
        else:
            message = f"Network data for {bmh_name} up-to-date or not applicable"
            updated = False

        return {
            'success': True if updated or matches else False,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Network data operation error: {str(e)[:50]}..."
        }

def userdata_present(namespace, bmh_name, pillar_data, userdata_template_path='salt://formulas/bmo/files/cloudinit.j2'):
    """
    Ensure that the userdata Secret in Kubernetes matches the desired state
    defined by pillar data and Jinja2 template.

    Args:
        namespace (str): The namespace of the userdata Secret in Kubernetes.
        bmh_name (str): The name of the Bare Metal Host resource (used for Secret naming).
        pillar_data (dict): Pillar data containing the desired userdata configuration.
        userdata_template_path (str, optional): Salt URI to the Jinja2 template file for userdata.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.userdata_present baremetal-operator-system compute-133-26 pillar_data
    """
    try:
        updated = False
        exists = False
        matches = False
        current_userdata = {}
        desired_userdata = {}
        differences = {}

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()
        userdata_name = f"{bmh_name}-user-data"

        if 'network' in pillar_data:
            try:
                userdata_secret = core_v1_api.read_namespaced_secret(name=userdata_name, namespace=namespace)
                exists = True
                current_userdata = userdata_secret.string_data if userdata_secret.string_data else {}
                if not current_userdata and userdata_secret.data:
                    import base64
                    current_userdata = {k: base64.b64decode(v).decode('utf-8') for k, v in userdata_secret.data.items()}
            except ApiException:
                exists = False
                current_userdata = {}
            except Exception:
                exists = False
                current_userdata = {}
        else:
            exists = False
            current_userdata = {}
            message = f"Userdata not applicable for {bmh_name}"
            return {
                'success': True,
                'updated': False,
                'message': message
            }

        if 'network' in pillar_data:
            try:
                full_pillar = __salt__['pillar.get']('', {})
                userdata_context = {
                    'pillar': {'node_deploy_key': full_pillar.get('node_deploy_key', '')},
                    'pass': pillar_data.get('root_password_crypted', '')
                }
                userdata_content = __salt__['cp.get_file_str'](userdata_template_path)
                if not userdata_content:
                    raise Exception(f"Empty userdata template at {userdata_template_path}")
                if userdata_content.startswith('#!'):
                    userdata_content = '\n'.join(userdata_content.splitlines()[1:]) if len(userdata_content.splitlines()) > 1 else ''
                rendered_userdata = __salt__['slsutil.renderer'](string=userdata_content, default_renderer='jinja', context=userdata_context)
                if not rendered_userdata:
                    raise Exception("Failed to render userdata template")

                desired_userdata = {'userData': rendered_userdata}

                if exists:
                    current_data = current_userdata.get('userData', '') if isinstance(current_userdata, dict) and 'userData' in current_userdata else (list(current_userdata.values())[0] if isinstance(current_userdata, dict) and len(current_userdata) == 1 else '')
                    desired_data = desired_userdata.get('userData', '')
                    if current_data != desired_data:
                        differences['userData'] = {'desired': desired_data[:50] + '...' if len(desired_data) > 50 else desired_data}
                    matches = len(differences) == 0
                else:
                    matches = False
            except Exception as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Userdata render failed: {str(e)[:50]}..."
                }
        else:
            desired_userdata = {}
            matches = False
            message = f"Userdata not applicable for {bmh_name}"
            return {
                'success': True,
                'updated': False,
                'message': message
            }

        if 'network' in pillar_data and (not exists or not matches):
            try:
                body = client.V1Secret(metadata=client.V1ObjectMeta(name=userdata_name, namespace=namespace), string_data=desired_userdata, type='Opaque')
                if exists:
                    core_v1_api.replace_namespaced_secret(name=userdata_name, namespace=namespace, body=body)
                    updated = True
                    message = f"Userdata Secret {userdata_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(namespace=namespace, body=body)
                    updated = True
                    message = f"Userdata Secret {userdata_name} created"
            except ApiException as e:
                updated = False
                message = f"Userdata Secret {userdata_name} operation failed: {str(e)[:50]}..."
        else:
            message = f"Userdata for {bmh_name} up-to-date or not applicable"
            updated = False

        return {
            'success': True if updated or matches else False,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Userdata operation error: {str(e)[:50]}..."
        }

def host_bmc_auth_present(namespace, bmh_name, ipmi, pillar_data, bmc_auth_template_path='salt://formulas/bmo/files/bmc-auth.j2'):
    """
    Ensure that a host-specific BMC authentication Secret in Kubernetes matches the desired state
    defined by pillar data and Jinja2 template.

    Args:
        namespace (str): The namespace of the Secret in Kubernetes.
        bmh_name (str): The name of the Bare Metal Host resource (used for Secret naming).
        ipmi (str): Default IPMI password if not in pillar.
        pillar_data (dict): Pillar data containing the desired BMC authentication configuration.
        bmc_auth_template_path (str, optional): Salt URI to the Jinja2 template file for BMC auth Secret.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.host_bmc_auth_present baremetal-operator-system compute-133-26 ipmi pillar_data
    """
    try:
        updated = False
        exists = False
        matches = False
        current_secret = {}
        desired_secret = {}
        differences = {}
        secret_name = f"{bmh_name}-bmc-auth"

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()

        try:
            secret = core_v1_api.read_namespaced_secret(name=secret_name, namespace=namespace)
            exists = True
            current_secret = secret.string_data if secret.string_data else {}
            if not current_secret and secret.data:
                import base64
                current_secret = {k: base64.b64decode(v).decode('utf-8') for k, v in secret.data.items()}
        except ApiException:
            exists = False
            current_secret = {}
        except Exception:
            exists = False
            current_secret = {}

        try:
            full_pillar = __salt__['pillar.get']('', {})
            bmc_auth_context = {
                'pillar': {
                    'name': bmh_name, 'bmo_namespace': full_pillar.get('bmo_namespace', namespace),
                    'ipmi_password': pillar_data.get('bmc', {}).get('password', full_pillar.get('ipmi-password', ipmi))
                }
            }
            bmc_auth_content = __salt__['cp.get_file_str'](bmc_auth_template_path)
            if not bmc_auth_content:
                raise Exception(f"Empty BMC auth template at {bmc_auth_template_path}")
            if bmc_auth_content.startswith('#!'):
                bmc_auth_content = '\n'.join(bmc_auth_content.splitlines()[1:]) if len(bmc_auth_content.splitlines()) > 1 else ''
            rendered_bmc_auth = __salt__['slsutil.renderer'](string=bmc_auth_content, default_renderer='jinja|yaml', context=bmc_auth_context)
            if not rendered_bmc_auth:
                raise Exception("Failed to render BMC auth template")

            import yaml
            desired_secret_full = rendered_bmc_auth if isinstance(rendered_bmc_auth, dict) else yaml.safe_load(rendered_bmc_auth)
            if 'metadata' in desired_secret_full:
                desired_secret_full['metadata']['name'] = secret_name
            desired_secret = desired_secret_full.get('stringData', {})

            if exists:
                for key in desired_secret:
                    if key not in current_secret or current_secret[key] != desired_secret[key]:
                        differences[key] = {'desired': desired_secret[key][:10] + '...' if len(desired_secret[key]) > 10 else desired_secret[key]}
                matches = len(differences) == 0
            else:
                matches = False
        except Exception as e:
            return {
                'success': False,
                'updated': False,
                'message': f"BMC auth render failed: {str(e)[:50]}..."
            }

        if not exists or not matches:
            try:
                body = client.V1Secret(metadata=client.V1ObjectMeta(name=secret_name, namespace=namespace), string_data=desired_secret, type=desired_secret_full.get('type', 'Opaque'))
                if exists:
                    core_v1_api.replace_namespaced_secret(name=secret_name, namespace=namespace, body=body)
                    updated = True
                    message = f"BMC Secret {secret_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(namespace=namespace, body=body)
                    updated = True
                    message = f"BMC Secret {secret_name} created"
            except ApiException as e:
                updated = False
                message = f"BMC Secret {secret_name} operation failed: {str(e)[:50]}..."
        else:
            message = f"BMC Secret {secret_name} up-to-date"
            updated = False

        return {
            'success': True if updated or matches else False,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"BMC auth operation error: {str(e)[:50]}..."
        }

def uuids_secret_present(namespace, secret_name, pillar_data, deployment_name="salt-master", wait_timeout=300, wait_interval=10):
    """
    Ensure that a Kubernetes Secret containing UUIDs from pillar data matches the desired state.
    If updated, restarts the specified deployment and waits for it to become ready. Assumes UUIDs are under 'salt-master:uuids'.

    Args:
        namespace (str): The namespace of the Secret and Deployment in Kubernetes.
        secret_name (str): The name of the Secret to create or update.
        pillar_data (dict): Pillar data containing the UUIDs under 'salt-master:uuids' as a string.
        deployment_name (str, optional): The name of the deployment to restart if updated. Defaults to 'salt-master'.
        wait_timeout (int, optional): Maximum time in seconds to wait for deployment readiness. Defaults to 300 (5 minutes).
        wait_interval (int, optional): Interval in seconds between checks for deployment readiness. Defaults to 10 seconds.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'restarted' (bool), 'waited' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.uuids_secret_present baremetal-operator-system salt-master-uuids pillar_data
    """
    try:
        updated = False
        restarted = False
        waited = False
        exists = False
        matches = False
        current_secret = {}
        desired_secret = {}
        differences = {}

        # Step 1: Safely extract UUIDs string from pillar data with detailed debugging
        uuids_str = ''
        debug_msg = "Pillar data structure: "
        if isinstance(pillar_data, dict):
            debug_msg += "dict; "
            salt_master_data = pillar_data.get('salt-master', {})
            if isinstance(salt_master_data, dict):
                debug_msg += "salt-master is dict; "
                uuids_str = salt_master_data.get('uuids', '')
                debug_msg += f"uuids found: {bool(uuids_str)}; "
            else:
                debug_msg += "salt-master is not dict; "
                uuids_str = salt_master_data if isinstance(salt_master_data, str) else ''
                debug_msg += f"uuids as string direct: {bool(uuids_str)}; "
        else:
            debug_msg += "not dict; "
            uuids_str = pillar_data if isinstance(pillar_data, str) else ''
            debug_msg += f"uuids as direct pillar_data: {bool(uuids_str)}; "

        # Check if UUIDs string is empty or whitespace-only
        if not uuids_str or uuids_str.strip() == '':
            return {
                'success': True,
                'updated': False,
                'restarted': False,
                'waited': False,
                'message': f"No UUIDs provided for Secret {secret_name}; no action taken. {debug_msg}"
            }

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()
        apps_v1_api = client.AppsV1Api()

        try:
            secret = core_v1_api.read_namespaced_secret(name=secret_name, namespace=namespace)
            exists = True
            current_secret = secret.string_data if secret.string_data else {}
            if not current_secret and secret.data:
                import base64
                current_secret = {k: base64.b64decode(v).decode('utf-8') for k, v in secret.data.items()}
        except ApiException:
            exists = False
            current_secret = {}
        except Exception:
            exists = False
            current_secret = {}

        desired_secret = {'uuids': uuids_str}

        if exists:
            for key in desired_secret:
                if key not in current_secret or current_secret[key] != desired_secret[key]:
                    differences[key] = {'desired': desired_secret[key][:50] + '...' if len(desired_secret[key]) > 50 else desired_secret[key]}
            matches = len(differences) == 0
        else:
            matches = False

        if not exists or not matches:
            try:
                body = client.V1Secret(metadata=client.V1ObjectMeta(name=secret_name, namespace=namespace), string_data=desired_secret, type='Opaque')
                if exists:
                    core_v1_api.replace_namespaced_secret(name=secret_name, namespace=namespace, body=body)
                    updated = True
                    message = f"UUID Secret {secret_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(namespace=namespace, body=body)
                    updated = True
                    message = f"UUID Secret {secret_name} created"
            except ApiException as e:
                updated = False
                message = f"UUID Secret {secret_name} operation failed: {str(e)[:50]}..."
        else:
            message = f"UUID Secret {secret_name} up-to-date"
            updated = False

        if updated:
            try:
                deployment = apps_v1_api.read_namespaced_deployment(name=deployment_name, namespace=namespace)
                selector = deployment.spec.selector.match_labels
                pods = core_v1_api.list_namespaced_pod(namespace=namespace, label_selector=','.join([f"{k}={v}" for k, v in selector.items()]))
                for pod in pods.items:
                    core_v1_api.delete_namespaced_pod(name=pod.metadata.name, namespace=namespace, body=client.V1DeleteOptions())
                restarted = True
                message += f"; {deployment_name} restarted"

                import time
                wait_time = 0
                while wait_time < wait_timeout:
                    try:
                        status = apps_v1_api.read_namespaced_deployment_status(name=deployment_name, namespace=namespace)
                        ready_replicas = status.status.ready_replicas or 0
                        desired_replicas = status.spec.replicas
                        if ready_replicas == desired_replicas:
                            waited = True
                            message += f"; {deployment_name} ready ({wait_time}s)"
                            break
                    except ApiException:
                        message += f"; {deployment_name} status check failed"
                        break
                    time.sleep(wait_interval)
                    wait_time += wait_interval
                if wait_time >= wait_timeout and not waited:
                    message += f"; {deployment_name} timeout ({wait_timeout}s)"
            except ApiException as e:
                restarted = False
                message += f"; {deployment_name} restart failed: {str(e)[:50]}..."
            except Exception as e:
                restarted = False
                message += f"; {deployment_name} restart error: {str(e)[:50]}..."

        return {
            'success': True if (updated and restarted and waited) or (matches and not updated) else False,
            'updated': updated,
            'restarted': restarted,
            'waited': waited,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'restarted': False,
            'waited': False,
            'message': f"UUID Secret operation error: {str(e)[:50]}..."
        }