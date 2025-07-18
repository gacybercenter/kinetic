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

def uuids_secret_present(namespace, secret_name, pillar_data, deployment_name="salt-master", wait_timeout=300, wait_interval=10, salt_check_timeout=120, salt_check_interval=5, salt_check_key="salt-master:uuids"):
    """
    Ensure that a Kubernetes Secret containing UUIDs from pillar data matches the desired state.
    Extracts UUIDs by looping through the 'bmh' dictionary in pillar data, collecting 'uuid' from each host.
    If updated, restarts the specified deployment, waits for it to become ready, and verifies salt-master responsiveness by fetching pillar data.

    Args:
        namespace (str): The namespace of the Secret and Deployment in Kubernetes.
        secret_name (str): The name of the Secret to create or update.
        pillar_data (dict): Pillar data containing the BMH hosts under 'bmh' with 'uuid' fields.
        deployment_name (str, optional): The name of the deployment to restart if updated. Defaults to 'salt-master'.
        wait_timeout (int, optional): Maximum time in seconds to wait for deployment readiness. Defaults to 300 (5 minutes).
        wait_interval (int, optional): Interval in seconds between checks for deployment readiness. Defaults to 10 seconds.
        salt_check_timeout (int, optional): Maximum time in seconds to wait for salt-master responsiveness. Defaults to 120 seconds.
        salt_check_interval (int, optional): Interval in seconds between salt-master responsiveness checks. Defaults to 5 seconds.
        salt_check_key (str, optional): The pillar key to fetch for checking salt-master responsiveness. Defaults to 'salt-master:uuids'.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'restarted' (bool), 'waited' (bool), 'salt_responded' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.uuids_secret_present baremetal-operator-system salt-master-uuids pillar_data
    """
    try:
        updated = False
        restarted = False
        waited = False
        salt_responded = False
        exists = False
        matches = False
        current_secret = {}
        desired_secret = {}
        differences = {}

        # Step 1: Extract UUIDs by looping through 'bmh' dictionary in pillar data
        uuids_list = []
        debug_msg = "Pillar data structure: "
        if isinstance(pillar_data, dict):
            debug_msg += "dict; "
            # Try to access 'bmh' directly in pillar_data or under 'bmh' key
            bmh_data = pillar_data.get('bmh', {})
            if not bmh_data or not isinstance(bmh_data, dict):
                debug_msg += "bmh not found or not dict; "
                # If 'bmh' is not found, check if pillar_data itself contains host entries (unlikely but for completeness)
                bmh_data = pillar_data if any(isinstance(v, dict) and 'uuid' in v for v in pillar_data.values()) else {}
                debug_msg += f"bmh as pillar_data: {bool(bmh_data)}; "
            else:
                debug_msg += "bmh found; "

            if bmh_data and isinstance(bmh_data, dict):
                # Loop through each host entry in bmh_data to extract 'uuid'
                for host_name, host_data in bmh_data.items():
                    if isinstance(host_data, dict) and 'uuid' in host_data:
                        uuid_val = host_data.get('uuid', '')
                        if uuid_val and isinstance(uuid_val, str):
                            uuids_list.append(uuid_val)
                debug_msg += f"extracted {len(uuids_list)} UUIDs from bmh hosts; "
                debug_msg += f"bmh host keys: {list(bmh_data.keys())[:5]}; "
            else:
                debug_msg += "no valid bmh data to extract UUIDs; "
        else:
            debug_msg += "not dict; "

        # Join the UUIDs into a single string with newlines
        uuids_str = '\n'.join(uuids_list) if uuids_list else ''
        debug_msg += f"uuids_str preview: {repr(uuids_str)[:50]}...; "

        # Check if UUIDs string is empty or whitespace-only
        if not uuids_str or uuids_str.strip() == '':
            return {
                'success': True,
                'updated': False,
                'restarted': False,
                'waited': False,
                'salt_responded': False,
                'message': f"No UUIDs extracted for Secret {secret_name}; no action taken. {debug_msg}"
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

        desired_secret = {'uuid': uuids_str}

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

                # Step 2: Wait for the deployment to become ready
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

                # Step 3: If deployment is ready, wait a mandatory 20 seconds before checking salt-master responsiveness
                if waited:
                    message += f"; Pausing for 20 seconds before salt-master responsiveness check"
                    time.sleep(20)
                    
                    # Step 4: Verify salt-master responsiveness by fetching pillar data
                    salt_check_time = 0
                    while salt_check_time < salt_check_timeout:
                        try:
                            # Attempt to fetch the specified pillar key to verify salt-master responsiveness
                            pillar_result = __salt__['pillar.get'](salt_check_key, default=None)
                            if pillar_result is not None:
                                salt_responded = True
                                message += f"; salt-master responded with pillar data for '{salt_check_key}' ({salt_check_time+20}s total)"
                                break
                            else:
                                message += f"; salt-master returned None for pillar key '{salt_check_key}' ({salt_check_time+20}s total), retrying..."
                        except Exception as pillar_err:
                            message += f"; salt-master pillar fetch error for '{salt_check_key}' ({salt_check_time+20}s total): {str(pillar_err)[:50]}..., retrying..."
                        time.sleep(salt_check_interval)
                        salt_check_time += salt_check_interval
                    if salt_check_time >= salt_check_timeout and not salt_responded:
                        message += f"; salt-master responsiveness timeout for pillar fetch ({salt_check_timeout+20}s total)"
            except ApiException as e:
                restarted = False
                message += f"; {deployment_name} restart failed: {str(e)[:50]}..."
            except Exception as e:
                restarted = False
                message += f"; {deployment_name} restart error: {str(e)[:50]}..."

        return {
            'success': True if (updated and restarted and waited and salt_responded) or (matches and not updated) else False,
            'updated': updated,
            'restarted': restarted,
            'waited': waited,
            'salt_responded': salt_responded,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'restarted': False,
            'waited': False,
            'salt_responded': False,
            'message': f"UUID Secret operation error: {str(e)[:50]}..."
        }
def mariadb_instance_present(namespace, instance_name, root_password, secret_name="mariadb-root-password", image="mariadb:10.6", storage_size="1Gi", storage_class="standard", pvc_name=None, replicas=1, limits_cpu="500m", limits_memory="512Mi", requests_cpu="200m", requests_memory="256Mi"):
    """
    Ensure that a MariaDB instance is present in Kubernetes using the MariaDB Operator.
    Creates or updates a root password Secret and the MariaDB instance Custom Resource with specified storage class, size, and optional PVC name.
    Checks if the associated PVC is available.

    Args:
        namespace (str): The namespace where the Secret and MariaDB instance will reside.
        instance_name (str): The name of the MariaDB instance.
        root_password (str): The root password for the MariaDB instance.
        secret_name (str, optional): The name of the Secret for the root password. Defaults to 'mariadb-root-password'.
        image (str, optional): The Docker image for MariaDB. Defaults to 'mariadb:10.6'.
        storage_size (str, optional): Storage size for MariaDB PVC. Defaults to '1Gi'.
        storage_class (str, optional): Storage class for MariaDB PVC. Defaults to 'standard'.
        pvc_name (str, optional): Optional name of an existing PVC to use for MariaDB storage. If not provided, the operator will create one based on storage_size and storage_class.
        replicas (int, optional): Number of replicas for MariaDB. Defaults to 1.
        limits_cpu (str, optional): CPU limit for MariaDB. Defaults to '500m'.
        limits_memory (str, optional): Memory limit for MariaDB. Defaults to '512Mi'.
        requests_cpu (str, optional): CPU request for MariaDB. Defaults to '200m'.
        requests_memory (str, optional): Memory request for MariaDB. Defaults to '256Mi'.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'secret_updated' (bool), 'pvc_available' (bool), and 'message' (str for status or error).

    CLI Example:
        salt '*' kinetic-k8s.mariadb_instance_present baremetal-operator-system ironic-mariadb mypassword storage_class=gp2 storage_size=5Gi pvc_name=my-custom-pvc
    """
    try:
        updated = False
        secret_updated = False
        secret_exists = False
        instance_exists = False
        instance_matches = False
        pvc_available = False
        differences = {}

        # Load Kubernetes configuration
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()
        custom_api = client.CustomObjectsApi()

        # Step 1: Manage the root password Secret
        try:
            secret = core_v1_api.read_namespaced_secret(name=secret_name, namespace=namespace)
            secret_exists = True
            current_password = secret.string_data.get('password', '') if secret.string_data else ''
            if not current_password and secret.data:
                import base64
                current_password = base64.b64decode(list(secret.data.values())[0]).decode('utf-8') if secret.data else ''
            if current_password != root_password:
                differences['password'] = {'desired': root_password[:3] + '...' if len(root_password) > 3 else root_password}
        except ApiException:
            secret_exists = False
        except Exception as e:
            secret_exists = False
            return {
                'success': False,
                'updated': False,
                'secret_updated': False,
                'pvc_available': False,
                'message': f"Error fetching Secret {secret_name}: {str(e)[:50]}..."
            }

        if not secret_exists or differences.get('password'):
            try:
                secret_body = client.V1Secret(
                    metadata=client.V1ObjectMeta(name=secret_name, namespace=namespace),
                    string_data={'password': root_password},
                    type='Opaque'
                )
                if secret_exists:
                    core_v1_api.replace_namespaced_secret(name=secret_name, namespace=namespace, body=secret_body)
                    secret_updated = True
                    message = f"Secret {secret_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(namespace=namespace, body=secret_body)
                    secret_updated = True
                    message = f"Secret {secret_name} created"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'secret_updated': False,
                    'pvc_available': False,
                    'message': f"Failed to update/create Secret {secret_name}: {str(e)[:50]}..."
                }
        else:
            message = f"Secret {secret_name} up-to-date"
            secret_updated = False

        # Step 2: Check if a specified PVC exists (if pvc_name is provided)
        if pvc_name:
            try:
                core_v1_api.read_namespaced_persistent_volume_claim(name=pvc_name, namespace=namespace)
                pvc_available = True
                message += f"; Specified PVC {pvc_name} found and available"
            except ApiException as e:
                if e.status == 404:
                    pvc_available = False
                    message += f"; Warning: Specified PVC {pvc_name} not found, will rely on operator to create a new PVC if not supported"
                else:
                    pvc_available = False
                    message += f"; Warning: Error checking specified PVC {pvc_name}: {str(e)[:50]}..."
            except Exception as e:
                pvc_available = False
                message += f"; Warning: General error checking specified PVC {pvc_name}: {str(e)[:50]}..."
        else:
            message += f"; No specific PVC name provided, relying on operator to create PVC with storageClass {storage_class} and size {storage_size}"

        # Step 3: Manage the MariaDB instance Custom Resource
        group = "k8s.mariadb.com"
        version = "v1alpha1"
        plural = "mariadbs"

        try:
            instance = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=namespace, plural=plural, name=instance_name
            )
            instance_exists = True
            current_spec = instance.get('spec', {})
            desired_spec = {
                'image': image,
                'storage': {'size': storage_size, 'storageClass': storage_class},
                'rootPasswordSecret': {'name': secret_name, 'key': 'password'},
                'replicas': replicas,
                'resources': {
                    'limits': {'cpu': limits_cpu, 'memory': limits_memory},
                    'requests': {'cpu': requests_cpu, 'memory': requests_memory}
                }
            }
            # If a specific PVC name is provided, note it in the spec (though MariaDB Operator may ignore it)
            if pvc_name:
                desired_spec['storage'].setdefault('pvcName', pvc_name)  # This is speculative; depends on operator support
            for key in desired_spec:
                if key not in current_spec or current_spec[key] != desired_spec[key]:
                    differences[key] = {'desired': desired_spec[key]}
            instance_matches = len(differences) == 0
        except ApiException:
            instance_exists = False
            differences = {'instance': {'desired': 'to be created'}}
        except Exception as e:
            instance_exists = False
            return {
                'success': False,
                'updated': False,
                'secret_updated': secret_updated,
                'pvc_available': pvc_available,
                'message': f"Error fetching MariaDB instance {instance_name}: {str(e)[:50]}..."
            }

        if not instance_exists or not instance_matches:
            try:
                instance_body = {
                    'apiVersion': f"{group}/{version}",
                    'kind': 'MariaDb',
                    'metadata': {'name': instance_name, 'namespace': namespace},
                    'spec': {
                        'image': image,
                        'storage': {'size': storage_size, 'storageClass': storage_class},
                        'rootPasswordSecret': {'name': secret_name, 'key': 'password'},
                        'replicas': replicas,
                        'resources': {
                            'limits': {'cpu': limits_cpu, 'memory': limits_memory},
                            'requests': {'cpu': requests_cpu, 'memory': requests_memory}
                        }
                    }
                }
                # If a specific PVC name is provided, add it to the spec (though MariaDB Operator may not use it)
                if pvc_name:
                    instance_body['spec']['storage'].setdefault('pvcName', pvc_name)  # Speculative; depends on operator
                if instance_exists:
                    if 'metadata' in instance and 'resourceVersion' in instance['metadata']:
                        instance_body['metadata']['resourceVersion'] = instance['metadata'].get('resourceVersion', '')
                    custom_api.replace_namespaced_custom_object(
                        group=group, version=version, namespace=namespace, plural=plural, name=instance_name, body=instance_body
                    )
                    updated = True
                    message += f"; MariaDB instance {instance_name} updated with storageClass {storage_class} and size {storage_size}"
                else:
                    custom_api.create_namespaced_custom_object(
                        group=group, version=version, namespace=namespace, plural=plural, body=instance_body
                    )
                    updated = True
                    message += f"; MariaDB instance {instance_name} created with storageClass {storage_class} and size {storage_size}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'secret_updated': secret_updated,
                    'pvc_available': pvc_available,
                    'message': f"Failed to create/update MariaDB instance {instance_name}: {str(e)[:100]}..."
                }
        else:
            message += f"; MariaDB instance {instance_name} up-to-date with storageClass {storage_class} and size {storage_size}"
            updated = False

        # Step 4: Verify PVC existence for the MariaDB instance (if pvc_name not provided, look for operator-created PVC)
        if not pvc_name:  # If no specific PVC name provided, try to find the operator-created PVC
            try:
                pvc_list = core_v1_api.list_namespaced_persistent_volume_claim(namespace=namespace)
                for pvc in pvc_list.items:
                    if instance_name in pvc.metadata.name:
                        pvc_available = True
                        pvc_name = pvc.metadata.name
                        message += f"; Operator-created PVC for {instance_name} found ({pvc_name})"
                        break
                if not pvc_available:
                    message += f"; Warning: No operator-created PVC found for {instance_name}, may still be provisioning"
            except ApiException as e:
                message += f"; Warning: Failed to check operator-created PVC for {instance_name}: {str(e)[:50]}..."
            except Exception as e:
                message += f"; Warning: Error checking operator-created PVC for {instance_name}: {str(e)[:50]}..."
        elif not pvc_available:  # If pvc_name was provided but not found earlier, note it again
            message += f"; Reminder: Specified PVC {pvc_name} was not found earlier, operator may have ignored it"

        return {
            'success': True if (updated or instance_matches) and (secret_updated or secret_exists) else False,
            'updated': updated,
            'secret_updated': secret_updated,
            'pvc_available': pvc_available,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'secret_updated': False,
            'pvc_available': False,
            'message': f"MariaDB operation error: {str(e)[:50]}..."
        }
def local_storage_pv_pvc_present(namespace, pv_name, pvc_name, storage_size="1Gi", node_name=None, path="/mnt/local-storage", storage_class="local-storage"):
    """
    Ensure that a Persistent Volume (PV) and Persistent Volume Claim (PVC) are present in Kubernetes using a specified storage class for local storage.
    The PV is tied to a local path. Checks if the local path exists on the node before proceeding.
    Also checks if both resources exist and are bound.

    Args:
        namespace (str): The namespace of the PVC (PV is cluster-wide but associated via PVC).
        pv_name (str): The name of the Persistent Volume.
        pvc_name (str): The name of the Persistent Volume Claim.
        storage_size (str, optional): Storage size for the PV and PVC. Defaults to '1Gi'.
        node_name (str, optional): The name of the node to bind the local storage PV to. Not used in this simplified version to avoid validation issues.
        path (str, optional): The host path on the node for local storage. Defaults to '/mnt/local-storage'.
        storage_class (str, optional): The storage class to use for the PV and PVC. Defaults to 'local-storage'.

    Returns:
        dict: A dictionary with 'success' (bool), 'pv_updated' (bool), 'pvc_updated' (bool), 'bound' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.local_storage_pv_pvc_present baremetal-operator-system local-pv-1 local-pvc-1 storage_size='5Gi' path='/mnt/local-storage' storage_class='local-storage'
    """
    try:
        pv_updated = False
        pvc_updated = False
        bound = False

        # Step 1: Check if the local path exists on the node
        if not __salt__['file.directory_exists'](path):
            return {
                'success': False,
                'pv_updated': False,
                'pvc_updated': False,
                'bound': False,
                'message': f"Local path {path} does not exist on the node. Please create the directory or specify a valid path before creating the PV."
            }

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()

        # Step 2: Check if PV exists
        try:
            existing_pv = core_v1_api.read_persistent_volume(name=pv_name)
            pv_exists = True
        except ApiException as e:
            if e.status == 404:
                pv_exists = False
            else:
                return {
                    'success': False,
                    'pv_updated': False,
                    'pvc_updated': False,
                    'bound': False,
                    'message': f"Error fetching PV {pv_name}: {str(e)[:100]}..."
                }

        # Step 3: Create or update PV if it doesn't exist or needs updating
        if not pv_exists:
            try:
                pv_body = client.V1PersistentVolume(
                    metadata=client.V1ObjectMeta(name=pv_name),
                    spec=client.V1PersistentVolumeSpec(
                        capacity={'storage': storage_size},
                        access_modes=["ReadWriteOnce"],
                        storage_class_name=storage_class,
                        host_path=client.V1HostPathVolumeSource(path=path)
                    )
                )
                core_v1_api.create_persistent_volume(body=pv_body)
                pv_updated = True
                message = f"PV {pv_name} created with size {storage_size} at {path}"
            except ApiException as e:
                return {
                    'success': False,
                    'pv_updated': False,
                    'pvc_updated': False,
                    'bound': False,
                    'message': f"Failed to create/update PV {pv_name}: {str(e)}"
                }
        else:
            message = f"PV {pv_name} already exists"
            pv_updated = False

        # Step 4: Check if PVC exists
        try:
            existing_pvc = core_v1_api.read_namespaced_persistent_volume_claim(name=pvc_name, namespace=namespace)
            pvc_exists = True
            # Check if PVC is bound to the PV
            if existing_pvc.status.phase == "Bound" and existing_pvc.spec.volume_name == pv_name:
                bound = True
            else:
                bound = False
        except ApiException as e:
            if e.status == 404:
                pvc_exists = False
                bound = False
            else:
                return {
                    'success': False,
                    'pv_updated': pv_updated,
                    'pvc_updated': False,
                    'bound': False,
                    'message': f"Error fetching PVC {pvc_name}: {str(e)[:100]}...; {message}"
                }

        # Step 5: Create or update PVC if it doesn't exist or needs updating
        if not pvc_exists:
            try:
                pvc_body = client.V1PersistentVolumeClaim(
                    metadata=client.V1ObjectMeta(name=pvc_name, namespace=namespace),
                    spec=client.V1PersistentVolumeClaimSpec(
                        resources=client.V1ResourceRequirements(
                            requests={'storage': storage_size}
                        ),
                        access_modes=["ReadWriteOnce"],
                        storage_class_name=storage_class,
                        volume_name=pv_name
                    )
                )
                core_v1_api.create_namespaced_persistent_volume_claim(namespace=namespace, body=pvc_body)
                pvc_updated = True
                message += f"; PVC {pvc_name} created with size {storage_size}"
            except ApiException as e:
                return {
                    'success': False,
                    'pv_updated': pv_updated,
                    'pvc_updated': False,
                    'bound': False,
                    'message': f"Failed to create/update PVC {pvc_name}: {str(e)[:100]}...; {message}"
                }
        else:
            message += f"; PVC {pvc_name} already exists"
            pvc_updated = False

        # Step 6: Check if PVC is bound to PV after creation/update
        if pvc_exists or pvc_updated:
            try:
                updated_pvc = core_v1_api.read_namespaced_persistent_volume_claim(name=pvc_name, namespace=namespace)
                if updated_pvc.status.phase == "Bound" and updated_pvc.spec.volume_name == pv_name:
                    bound = True
                    message += f"; PVC {pvc_name} is bound to PV {pv_name}"
                else:
                    bound = False
                    message += f"; PVC {pvc_name} is not bound to PV {pv_name} (status: {updated_pvc.status.phase})"
            except ApiException as e:
                bound = False
                message += f"; Failed to check PVC {pvc_name} binding status: {str(e)[:100]}..."

        return {
            'success': True if (pv_updated or pvc_updated or bound) else False,
            'pv_updated': pv_updated,
            'pvc_updated': pvc_updated,
            'bound': bound,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'pv_updated': False,
            'pvc_updated': False,
            'bound': False,
            'message': f"Local storage PV/PVC operation error: {str(e)[:100]}..."
        }
}