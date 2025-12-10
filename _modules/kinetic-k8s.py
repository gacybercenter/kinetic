# -*- coding: utf-8 -*-
"""
SaltStack execution module for interacting with Kubernetes to retrieve hardware data.

This module provides functions to query Kubernetes Custom Resources, specifically
for retrieving MAC addresses from HardwareData resources in a Metal3.io environment.
"""

import salt.utils.decorators as decorators
from kubernetes import client, config
from kubernetes.client.rest import ApiException
import base64

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
def mariadb_instance_present(namespace, instance_name, root_password, secret_name, image="mariadb:10.6", pvc_name="mariadb-pvc", storage_size="1Gi", storage_class="local-storage", replicas=1, limits_cpu="500m", limits_memory="512Mi", requests_cpu="200m", requests_memory="256Mi", admin_host_access="%"):
    """
    Ensure that a MariaDB instance is present in Kubernetes using the MariaDB Operator.
    Creates a Secret for the root password if it doesn't exist, then creates or updates the MariaDB Custom Resource.
    Additionally, ensures the root user has access from the specified host or IP pattern.

    Args:
        namespace (str): The namespace of the MariaDB instance and Secret in Kubernetes.
        instance_name (str): The name of the MariaDB instance (Custom Resource).
        root_password (str): The root password for MariaDB (stored in a Secret).
        secret_name (str): The name of the Secret to store the root password.
        image (str, optional): The MariaDB Docker image to use. Defaults to 'mariadb:10.6'.
        pvc_name (str, optional): Ignored since operator creates PVC. Kept for compatibility. Defaults to 'mariadb-pvc'.
        storage_size (str, optional): Storage size for the PVC. Defaults to '1Gi'.
        storage_class (str, optional): Storage class for the PVC. Defaults to 'local-storage'.
        replicas (int, optional): Number of replicas for the MariaDB instance. Defaults to 1.
        limits_cpu (str, optional): CPU limit for the MariaDB container. Defaults to '500m'.
        limits_memory (str, optional): Memory limit for the MariaDB container. Defaults to '512Mi'.
        requests_cpu (str, optional): CPU request for the MariaDB container. Defaults to '200m'.
        requests_memory (str, optional): Memory request for the MariaDB container. Defaults to '256Mi'.
        admin_host_access (str, optional): Host or IP pattern to grant root access from. Defaults to '%'.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'secret_updated' (bool), 'pvc_available' (bool), 'root_access_updated' (bool), and 'message' (str).
    """
    try:
        updated = False
        secret_updated = False
        root_access_updated = False
        secret_exists = False
        mariadb_exists = False
        matches = False
        pvc_available = False

        message = f"Configuring MariaDB with storage class: {storage_class}"

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()
        custom_api = client.CustomObjectsApi()

        # Step 1: Check if Secret for root password exists
        try:
            secret = core_v1_api.read_namespaced_secret(name=secret_name, namespace=namespace)
            secret_exists = True
            current_password = secret.string_data.get('password', '') if secret.string_data else ''
            if not current_password and secret.data:
                import base64
                current_password = base64.b64decode(secret.data.get('password', '')).decode('utf-8')
            if current_password != root_password:
                secret_updated = True
            else:
                secret_updated = False
        except ApiException as e:
            if e.status == 404:
                secret_exists = False
                secret_updated = True
            else:
                return {
                    'success': False,
                    'updated': False,
                    'secret_updated': False,
                    'pvc_available': False,
                    'root_access_updated': False,
                    'message': f"Error fetching Secret {secret_name}: {str(e)[:100]}...; {message}"
                }

        # Step 2: Create or update Secret if necessary
        if not secret_exists or secret_updated:
            try:
                secret_body = client.V1Secret(
                    metadata=client.V1ObjectMeta(name=secret_name, namespace=namespace),
                    string_data={'password': root_password},
                    type='Opaque'
                )
                if secret_exists:
                    core_v1_api.replace_namespaced_secret(name=secret_name, namespace=namespace, body=secret_body)
                    message += f"; Secret {secret_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(namespace=namespace, body=secret_body)
                    message += f"; Secret {secret_name} created"
                secret_updated = True
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'secret_updated': False,
                    'pvc_available': False,
                    'root_access_updated': False,
                    'message': f"Failed to create/update Secret {secret_name}: {str(e)[:100]}...; {message}"
                }
        else:
            message += f"; Secret {secret_name} already up-to-date"

        # Step 3: Check if MariaDB instance exists
        try:
            group = "k8s.mariadb.com"
            version = "v1alpha1"
            plural = "mariadbs"
            mariadb = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=namespace, plural=plural, name=instance_name
            )
            mariadb_exists = True
            # Check if key fields match desired state for potential update
            current_spec = mariadb.get('spec', {})
            desired_image = image
            desired_replicas = replicas
            current_image = current_spec.get('image', '')
            current_replicas = current_spec.get('replicas', 1)
            current_storage = current_spec.get('storage', {})
            current_storage_class = current_storage.get('storageClassName', '')
            current_storage_size = current_storage.get('size', '')
            if (current_image != desired_image or
                current_replicas != desired_replicas or
                current_storage_size != storage_size or
                current_storage_class != storage_class):
                matches = False
            else:
                matches = True
        except ApiException as e:
            if e.status == 404:
                mariadb_exists = False
                matches = False
            else:
                return {
                    'success': False,
                    'updated': False,
                    'secret_updated': secret_updated,
                    'pvc_available': False,
                    'root_access_updated': False,
                    'message': f"Error fetching MariaDB instance {instance_name}: {str(e)[:100]}...; {message}"
                }

        # Step 4: No PVC check since operator will create it
        pvc_available = False
        message += f"; Skipping PVC check, operator will create PVC with storage class {storage_class}"

        # Step 5: Create or update MariaDB instance if necessary
        if not mariadb_exists or not matches:
            try:
                group = "k8s.mariadb.com"
                version = "v1alpha1"
                plural = "mariadbs"
                mariadb_body = {
                    "apiVersion": f"{group}/{version}",
                    "kind": "MariaDb",
                    "metadata": {
                        "name": instance_name,
                        "namespace": namespace
                    },
                    "spec": {
                        "image": image,
                        "username": "root",
                        "passwordSecretKeyRef": {
                            "name": secret_name,
                            "key": "password"
                        },
                        "replicas": replicas,
                        "resources": {
                            "limits": {
                                "cpu": limits_cpu,
                                "memory": limits_memory
                            },
                            "requests": {
                                "cpu": requests_cpu,
                                "memory": requests_memory
                            }
                        },
                        "storage": {
                            "size": storage_size,
                            "storageClassName": storage_class,
                            "accessModes": ["ReadWriteOnce"]
                        }
                    }
                }
                if mariadb_exists:
                    custom_api.replace_namespaced_custom_object(
                        group=group, version=version, namespace=namespace, plural=plural, name=instance_name, body=mariadb_body
                    )
                    updated = True
                    message += f"; MariaDB instance {instance_name} updated"
                else:
                    custom_api.create_namespaced_custom_object(
                        group=group, version=version, namespace=namespace, plural=plural, body=mariadb_body
                    )
                    updated = True
                    message += f"; MariaDB instance {instance_name} created"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'secret_updated': secret_updated,
                    'pvc_available': pvc_available,
                    'root_access_updated': False,
                    'message': f"Failed to create/update MariaDB instance {instance_name}: {str(e)[:100]}...; {message}"
                }
        else:
            message += f"; MariaDB instance {instance_name} already up-to-date"
            updated = False

        # Step 6: Ensure root user has access from the specified host/IP pattern
        try:
            # Get the MariaDB pod name
            pod_list = core_v1_api.list_namespaced_pod(namespace=namespace, label_selector=f"app.kubernetes.io/name={instance_name}")
            if pod_list.items:
                pod_name = pod_list.items[0].metadata.name
                # Construct the kubectl exec command to grant root access
                grant_cmd = f"mysql -u root -p{root_password} -e \"GRANT ALL PRIVILEGES ON *.* TO 'root'@'{admin_host_access}' IDENTIFIED BY '{root_password}' WITH GRANT OPTION; FLUSH PRIVILEGES;\""
                kubectl_cmd = f"kubectl exec -i {pod_name} -n {namespace} -- {grant_cmd}"
                # Execute the command using Salt's cmd.run
                grant_result = __salt__['cmd.run'](kubectl_cmd, shell=True, ignore_retcode=True)
                if "ERROR" not in grant_result:
                    root_access_updated = True
                    message += f"; Root user access granted for host {admin_host_access}"
                else:
                    root_access_updated = False
                    message += f"; Failed to grant root access for host {admin_host_access}: {grant_result[:100]}..."
            else:
                root_access_updated = False
                message += f"; No MariaDB pod found for {instance_name} to grant root access"
        except Exception as e:
            root_access_updated = False
            message += f"; Error granting root access for host {admin_host_access}: {str(e)[:100]}..."

        return {
            'success': True if (updated or matches) else False,
            'updated': updated,
            'secret_updated': secret_updated,
            'pvc_available': pvc_available,
            'root_access_updated': root_access_updated,
            'message': message
        }
    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'secret_updated': False,
            'pvc_available': False,
            'root_access_updated': False,
            'message': f"MariaDB instance operation error: {str(e)[:100]}..."
        }
def local_storage_pv_pvc_present(namespace, pv_name, pvc_name, storage_size="1Gi", node_name=None, path="/mnt/local-storage", storage_class="local-storage"):
    """
    Ensure that a Persistent Volume (PV) is present in Kubernetes using a specified storage class for local storage.
    The PV is tied to a local path. Checks if the local path exists on the node before proceeding.
    Does not manage PVC creation since the operator will handle it. Sanitizes PV name to meet Kubernetes naming conventions.

    Args:
        namespace (str): The namespace of the PVC (unused since PVC is not created, kept for compatibility).
        pv_name (str): The name of the Persistent Volume (will be sanitized).
        pvc_name (str): Ignored since PVC is not created. Kept for compatibility.
        storage_size (str, optional): Storage size for the PV. Defaults to '1Gi'.
        node_name (str, optional): The name of the node to bind the local storage PV to. Not used in this simplified version to avoid validation issues.
        path (str, optional): The host path on the node for local storage. Defaults to '/mnt/local-storage'.
        storage_class (str, optional): The storage class to use for the PV. Defaults to 'local-storage'.

    Returns:
        dict: A dictionary with 'success' (bool), 'pv_updated' (bool), 'pvc_updated' (bool), 'bound' (bool), and 'message' (str).
    """
    try:
        pv_updated = False
        pvc_updated = False
        bound = False

        # Sanitize pv_name to meet Kubernetes naming conventions
        def sanitize_name(name):
            import re
            # Convert to lowercase
            sanitized = name.lower()
            # Replace invalid characters with hyphens
            sanitized = re.sub(r'[^a-z0-9.-]', '-', sanitized)
            # Remove leading/trailing hyphens or periods
            sanitized = sanitized.strip('-').strip('.')
            # Truncate to 253 characters (Kubernetes max for most resource names)
            sanitized = sanitized[:253]
            # If empty after sanitization, provide a fallback
            if not sanitized:
                sanitized = "sanitized-name"
            return sanitized

        original_pv_name = pv_name
        pv_name = sanitize_name(pv_name)
        message = f"Sanitized PV name: {original_pv_name} -> {pv_name}; PVC management skipped, operator will handle PVC creation"

        # Step 1: Ensure the local path exists on the node
        if not __salt__['file.directory_exists'](path):
            try:
                __salt__['file.mkdir'](path)
                message += f"; Created directory {path} on node"
            except Exception as e:
                return {
                    'success': False,
                    'pv_updated': False,
                    'pvc_updated': False,
                    'bound': False,
                    'message': f"Failed to create directory {path} on node: {str(e)[:100]}...; {message}"
                }
        else:
            message += f"; Directory {path} already exists on node"

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
                    'message': f"Error fetching PV {pv_name}: {str(e)[:100]}...; {message}"
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
                message += f"; PV {pv_name} created with size {storage_size} at {path}"
            except ApiException as e:
                return {
                    'success': False,
                    'pv_updated': False,
                    'pvc_updated': False,
                    'bound': False,
                    'message': f"Failed to create/update PV {pv_name}: {str(e)[:100]}...; {message}"
                }
        else:
            message += f"; PV {pv_name} already exists"
            pv_updated = False

        # Step 4: Skip PVC creation and binding check since operator handles PVC
        message += f"; PVC creation and binding skipped, relying on operator to create PVC with storage class {storage_class}"

        return {
            'success': True if pv_updated or pv_exists else False,
            'pv_updated': pv_updated,
            'pvc_updated': False,
            'bound': False,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'pv_updated': False,
            'pvc_updated': False,
            'bound': False,
            'message': f"Local storage PV operation error: {str(e)[:100]}..."
        }
def ironic_db_user_setup(namespace, mariadb_name, mariadb_namespace, user_name, user_password, secret_name, database_name="ironic-database", host="%", max_user_connections=100, privileges=["ALL PRIVILEGES"], table="*"):
    """
    Ensure that the necessary Kubernetes resources for an Ironic database user are present.
    This includes a Secret for user credentials, a User custom resource, a Database custom resource, and a Grant custom resource.

    Args:
        namespace (str): The namespace for the Secret, User, Database, and Grant resources (typically Ironic namespace).
        mariadb_name (str): The name of the MariaDB instance (Custom Resource) to reference.
        mariadb_namespace (str): The namespace of the MariaDB instance.
        user_name (str): The username for the database user (must match Secret data and User metadata name).
        user_password (str): The password for the database user.
        secret_name (str): The name of the Secret to store the user credentials.
        database_name (str, optional): The name of the database to grant privileges on. Defaults to 'ironic-database'.
        host (str, optional): The host pattern for user access. Defaults to '%'.
        max_user_connections (int, optional): Maximum connections for the user. Defaults to 100.
        privileges (list, optional): List of privileges to grant. Defaults to ['ALL PRIVILEGES'].
        table (str, optional): Table pattern for privileges. Defaults to '*'.

    Returns:
        dict: A dictionary with 'success' (bool), 'secret_updated' (bool), 'user_updated' (bool), 'database_updated' (bool), 'grant_updated' (bool), and 'message' (str).
    """
    try:
        secret_updated = False
        user_updated = False
        database_updated = False
        grant_updated = False
        secret_exists = False
        user_exists = False
        database_exists = False
        grant_exists = False
        secret_matches = False
        user_matches = False
        database_matches = False
        grant_matches = False

        message = f"Setting up Ironic DB user {user_name} for database {database_name} in namespace {namespace}"

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()
        custom_api = client.CustomObjectsApi()

        # Step 1: Check if Secret for user credentials exists
        try:
            secret = core_v1_api.read_namespaced_secret(name=secret_name, namespace=namespace)
            secret_exists = True
            current_username = secret.string_data.get('username', '') if secret.string_data else ''
            current_password = secret.string_data.get('password', '') if secret.string_data else ''
            if not current_username and secret.data:
                import base64
                current_username = base64.b64decode(secret.data.get('username', '')).decode('utf-8')
                current_password = base64.b64decode(secret.data.get('password', '')).decode('utf-8')
            if current_username != user_name or current_password != user_password:
                secret_updated = True
            else:
                secret_matches = True
                secret_updated = False
        except ApiException as e:
            if e.status == 404:
                secret_exists = False
                secret_updated = True
            else:
                return {
                    'success': False,
                    'secret_updated': False,
                    'user_updated': False,
                    'database_updated': False,
                    'grant_updated': False,
                    'message': f"Error fetching Secret {secret_name}: {str(e)[:100]}...; {message}"
                }

        # Step 2: Create or update Secret if necessary
        if not secret_exists or secret_updated:
            try:
                secret_body = client.V1Secret(
                    metadata=client.V1ObjectMeta(name=secret_name, namespace=namespace),
                    string_data={'username': user_name, 'password': user_password},
                    type='Opaque'
                )
                if secret_exists:
                    core_v1_api.replace_namespaced_secret(name=secret_name, namespace=namespace, body=secret_body)
                    secret_updated = True
                    message += f"; Secret {secret_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(namespace=namespace, body=secret_body)
                    secret_updated = True
                    message += f"; Secret {secret_name} created"
            except ApiException as e:
                return {
                    'success': False,
                    'secret_updated': False,
                    'user_updated': False,
                    'database_updated': False,
                    'grant_updated': False,
                    'message': f"Failed to create/update Secret {secret_name}: {str(e)[:100]}...; {message}"
                }
        else:
            message += f"; Secret {secret_name} credentials match, no update needed"

        # Step 3: Check if User custom resource exists
        try:
            group = "k8s.mariadb.com"
            version = "v1alpha1"
            plural = "users"
            user = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=namespace, plural=plural, name=user_name
            )
            user_exists = True
            current_user_spec = user.get('spec', {})
            current_mariadb_ref = current_user_spec.get('mariaDbRef', {})
            if (current_mariadb_ref.get('name', '') != mariadb_name or
                current_mariadb_ref.get('namespace', '') != mariadb_namespace or
                current_user_spec.get('host', '') != host or
                current_user_spec.get('maxUserConnections', 0) != max_user_connections):
                user_matches = False
            else:
                user_matches = True
        except ApiException as e:
            if e.status == 404:
                user_exists = False
                user_matches = False
            else:
                return {
                    'success': False,
                    'secret_updated': secret_updated,
                    'user_updated': False,
                    'database_updated': False,
                    'grant_updated': False,
                    'message': f"Error fetching User {user_name}: {str(e)[:100]}...; {message}"
                }

        # Step 4: Create or update User if necessary
        if not user_exists or not user_matches:
            try:
                user_body = {
                    "apiVersion": f"{group}/{version}",
                    "kind": "User",
                    "metadata": {
                        "name": user_name,
                        "namespace": namespace
                    },
                    "spec": {
                        "mariaDbRef": {
                            "name": mariadb_name,
                            "namespace": mariadb_namespace,
                            "waitForIt": True
                        },
                        "cleanupPolicy": "Delete",
                        "host": host,
                        "maxUserConnections": max_user_connections,
                        "passwordSecretKeyRef": {
                            "name": secret_name,
                            "key": "password"
                        }
                    }
                }
                if user_exists and 'metadata' in user and 'resourceVersion' in user['metadata']:
                    user_body['metadata']['resourceVersion'] = user['metadata']['resourceVersion']
                if user_exists:
                    custom_api.replace_namespaced_custom_object(
                        group=group, version=version, namespace=namespace, plural=plural, name=user_name, body=user_body
                    )
                    user_updated = True
                    message += f"; User {user_name} updated"
                else:
                    custom_api.create_namespaced_custom_object(
                        group=group, version=version, namespace=namespace, plural=plural, body=user_body
                    )
                    user_updated = True
                    message += f"; User {user_name} created"
            except ApiException as e:
                error_details = str(e)
                if hasattr(e, 'body') and e.body:
                    error_details += f"; Full Response Body: {e.body[:1000] if len(e.body) > 1000 else e.body}"
                elif hasattr(e, 'reason'):
                    error_details += f"; Reason: {e.reason}"
                return {
                    'success': False,
                    'secret_updated': secret_updated,
                    'user_updated': False,
                    'database_updated': False,
                    'grant_updated': False,
                    'message': f"Failed to create/update User {user_name}: {error_details}; {message}"
                }
        else:
            message += f"; User {user_name} spec matches, no update needed"

        # Step 5: Check if Database custom resource exists
        try:
            plural = "databases"
            database = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=namespace, plural=plural, name=database_name
            )
            database_exists = True
            current_database_spec = database.get('spec', {})
            current_mariadb_ref = current_database_spec.get('mariaDbRef', {})
            if (current_mariadb_ref.get('name', '') != mariadb_name or
                current_mariadb_ref.get('namespace', '') != mariadb_namespace):
                database_matches = False
            else:
                database_matches = True
        except ApiException as e:
            if e.status == 404:
                database_exists = False
                database_matches = False
            else:
                return {
                    'success': False,
                    'secret_updated': secret_updated,
                    'user_updated': user_updated,
                    'database_updated': False,
                    'grant_updated': False,
                    'message': f"Error fetching Database {database_name}: {str(e)[:100]}...; {message}"
                }

        # Step 6: Create or update Database if necessary
        if not database_exists or not database_matches:
            try:
                database_body = {
                    "apiVersion": f"{group}/{version}",
                    "kind": "Database",
                    "metadata": {
                        "name": database_name,
                        "namespace": namespace
                    },
                    "spec": {
                        "mariaDbRef": {
                            "name": mariadb_name,
                            "namespace": mariadb_namespace,
                            "waitForIt": True
                        },
                        "cleanupPolicy": "Delete",
                        "characterSet": "utf8",
                        "collate": "utf8_general_ci"
                    }
                }
                if database_exists and 'metadata' in database and 'resourceVersion' in database['metadata']:
                    database_body['metadata']['resourceVersion'] = database['metadata']['resourceVersion']
                if database_exists:
                    custom_api.replace_namespaced_custom_object(
                        group=group, version=version, namespace=namespace, plural=plural, name=database_name, body=database_body
                    )
                    database_updated = True
                    message += f"; Database {database_name} updated"
                else:
                    custom_api.create_namespaced_custom_object(
                        group=group, version=version, namespace=namespace, plural=plural, body=database_body
                    )
                    database_updated = True
                    message += f"; Database {database_name} created"
            except ApiException as e:
                error_details = str(e)
                if hasattr(e, 'body') and e.body:
                    error_details += f"; Full Response Body: {e.body[:1000] if len(e.body) > 1000 else e.body}"
                elif hasattr(e, 'reason'):
                    error_details += f"; Reason: {e.reason}"
                return {
                    'success': False,
                    'secret_updated': secret_updated,
                    'user_updated': user_updated,
                    'database_updated': False,
                    'grant_updated': False,
                    'message': f"Failed to create/update Database {database_name}: {error_details}; {message}"
                }
        else:
            message += f"; Database {database_name} spec matches, no update needed"

        # Step 7: Check if Grant custom resource exists
        grant_name = f"{user_name}-grant"
        try:
            plural = "grants"
            # Use mariadb_namespace for Grant to ensure it's in the same namespace as MariaDB instance
            grant = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=mariadb_namespace, plural=plural, name=grant_name
            )
            grant_exists = True
            current_grant_spec = grant.get('spec', {})
            current_mariadb_ref = current_grant_spec.get('mariaDbRef', {})
            current_privileges = current_grant_spec.get('privileges', [])
            if (current_mariadb_ref.get('name', '') != mariadb_name or
                current_mariadb_ref.get('namespace', '') != mariadb_namespace or
                current_grant_spec.get('database', '') != database_name or
                current_grant_spec.get('host', '') != host or
                current_grant_spec.get('username', '') != user_name or
                (current_grant_spec.get('table', '*') != table if 'table' in current_grant_spec else True) or
                sorted(current_privileges) != sorted(privileges)):
                grant_matches = False
            else:
                grant_matches = True
        except ApiException as e:
            if e.status == 404:
                grant_exists = False
                grant_matches = False
            else:
                return {
                    'success': False,
                    'secret_updated': secret_updated,
                    'user_updated': user_updated,
                    'database_updated': database_updated,
                    'grant_updated': False,
                    'message': f"Error fetching Grant {grant_name}: {str(e)[:100]}...; {message}"
                }

        # Step 8: Create or update Grant if necessary with a minimal spec first
        if not grant_exists or not grant_matches:
            try:
                plural = "grants"
                # Use mariadb_namespace for Grant to ensure it's in the same namespace as MariaDB instance
                grant_body = {
                    "apiVersion": f"{group}/{version}",
                    "kind": "Grant",
                    "metadata": {
                        "name": grant_name,
                        "namespace": mariadb_namespace
                    },
                    "spec": {
                        "mariaDbRef": {
                            "name": mariadb_name,
                            "namespace": mariadb_namespace,
                            "waitForIt": True
                        },
                        "cleanupPolicy": "Delete",
                        "database": database_name,
                        "host": host,
                        "privileges": privileges,
                        "username": user_name
                    }
                }
                if grant_exists and 'metadata' in grant and 'resourceVersion' in grant['metadata']:
                    grant_body['metadata']['resourceVersion'] = grant['metadata']['resourceVersion']
                if grant_exists:
                    custom_api.replace_namespaced_custom_object(
                        group=group, version=version, namespace=mariadb_namespace, plural=plural, name=grant_name, body=grant_body
                    )
                    grant_updated = True
                    message += f"; Grant {grant_name} updated"
                else:
                    custom_api.create_namespaced_custom_object(
                        group=group, version=version, namespace=mariadb_namespace, plural=plural, body=grant_body
                    )
                    grant_updated = True
                    message += f"; Grant {grant_name} created"
            except ApiException as e:
                error_details = f"Status: {e.status if hasattr(e, 'status') else 'Unknown'}, Reason: {e.reason if hasattr(e, 'reason') else 'Unknown'}"
                if hasattr(e, 'body') and e.body:
                    error_details += f"; Full Response Body: {e.body[:1000] if len(e.body) > 1000 else e.body}"
                elif hasattr(e, 'headers'):
                    error_details += f"; Headers: {e.headers}"
                message += f"; DEBUG - Attempted Grant spec in namespace {mariadb_namespace}: {grant_body['spec']}"
                return {
                    'success': False,
                    'secret_updated': secret_updated,
                    'user_updated': user_updated,
                    'database_updated': database_updated,
                    'grant_updated': False,
                    'message': f"Failed to create/update Grant {grant_name}: {error_details}; {message}"
                }
        else:
            message += f"; Grant {grant_name} spec matches, no update needed"

        return {
            'success': True if (secret_updated or user_updated or database_updated or grant_updated or (secret_matches and user_matches and database_matches and grant_matches)) else False,
            'secret_updated': secret_updated,
            'user_updated': user_updated,
            'database_updated': database_updated,
            'grant_updated': grant_updated,
            'message': message
        }
    except Exception as e:
        error_details = f"General Exception: {str(e)}"
        return {
            'success': False,
            'secret_updated': False,
            'user_updated': False,
            'database_updated': False,
            'grant_updated': False,
            'message': f"Ironic DB user setup error: {error_details}; {message}"
        }
def mariadb_database_present(namespace, database_name, mariadb_name, mariadb_namespace, character_set="utf8", collate="utf8_general_ci", cleanup_policy="Delete"):
    """
    Ensure that a Database custom resource is present in Kubernetes using the MariaDB Operator.
    Creates or updates the Database resource to ensure a specific database exists in the MariaDB instance.

    Args:
        namespace (str): The namespace for the Database resource (often the same as the application namespace).
        database_name (str): The name of the Database resource and the actual database in MariaDB.
        mariadb_name (str): The name of the MariaDB instance to reference.
        mariadb_namespace (str): The namespace of the MariaDB instance.
        character_set (str, optional): The character set for the database. Defaults to 'utf8'.
        collate (str, optional): The collation for the database. Defaults to 'utf8_general_ci'.
        cleanup_policy (str, optional): Cleanup policy for the resource. Defaults to 'Delete'.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).
    """
    try:
        updated = False
        exists = False
        matches = False

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        group = "k8s.mariadb.com"
        version = "v1alpha1"
        plural = "databases"

        message = f"Configuring Database {database_name} in namespace {namespace}"

        # Check if Database resource exists
        try:
            database = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=namespace, plural=plural, name=database_name
            )
            exists = True
            current_spec = database.get('spec', {})
            desired_spec = {
                "mariaDbRef": {
                    "name": mariadb_name,
                    "namespace": mariadb_namespace,
                    "waitForIt": True
                },
                "characterSet": character_set,
                "cleanupPolicy": cleanup_policy,
                "collate": collate
            }
            # Compare current spec with desired spec
            matches = current_spec == desired_spec
        except ApiException as e:
            if e.status == 404:
                exists = False
                matches = False
            else:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Error fetching Database {database_name}: {str(e)[:100]}...; {message}"
                }

        # Create or update Database if necessary
        if not exists or not matches:
            try:
                database_body = {
                    "apiVersion": f"{group}/{version}",
                    "kind": "Database",
                    "metadata": {
                        "name": database_name,
                        "namespace": namespace
                    },
                    "spec": {
                        "mariaDbRef": {
                            "name": mariadb_name,
                            "namespace": mariadb_namespace,
                            "waitForIt": True
                        },
                        "characterSet": character_set,
                        "cleanupPolicy": cleanup_policy,
                        "collate": collate
                    }
                }
                if exists:
                    # Include resourceVersion for update
                    if 'metadata' in database and 'resourceVersion' in database['metadata']:
                        database_body['metadata']['resourceVersion'] = database['metadata']['resourceVersion']
                    custom_api.replace_namespaced_custom_object(
                        group=group, version=version, namespace=namespace, plural=plural, name=database_name, body=database_body
                    )
                    updated = True
                    message += f"; Database {database_name} updated"
                else:
                    custom_api.create_namespaced_custom_object(
                        group=group, version=version, namespace=namespace, plural=plural, body=database_body
                    )
                    updated = True
                    message += f"; Database {database_name} created"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to create/update Database {database_name}: Status: {e.status}, Reason: {e.reason}; Full Response Body: {str(e.body)[:500]}...; {message}"
                }
        else:
            message += f"; Database {database_name} already up-to-date"
            updated = False

        return {
            'success': True if (updated or matches) else False,
            'updated': updated,
            'message': message
        }
    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Database operation error for {database_name}: {str(e)[:100]}..."
        }
def generate_tls_secret(namespace, secret_name, common_name="ironic-operator", validity_days=365):
    """
    Generate a TLS key pair (private key and certificate) and store them in a Kubernetes Secret.
    This is useful for securing communications, such as for the Ironic Standalone Operator.

    Args:
        namespace (str): The Kubernetes namespace where the Secret will be created.
        secret_name (str): The name of the Secret to store the TLS key pair.
        common_name (str, optional): The Common Name (CN) for the certificate subject. Defaults to 'ironic-operator'.
        validity_days (int, optional): The number of days the certificate is valid for. Defaults to 365 (1 year).

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).
    """
    try:
        updated = False
        exists = False

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()

        message = f"Generating TLS key pair for Secret {secret_name} in namespace {namespace}"

        # Check if Secret already exists
        try:
            core_v1_api.read_namespaced_secret(name=secret_name, namespace=namespace)
            exists = True
            message += f"; Secret {secret_name} already exists, skipping generation"
            return {
                'success': True,
                'updated': False,
                'message': message
            }
        except ApiException as e:
            if e.status == 404:
                exists = False
            else:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Error checking Secret {secret_name}: {str(e)[:100]}...; {message}"
                }

        # Generate TLS key pair if Secret does not exist
        try:
            from cryptography import x509
            from cryptography.x509.oid import NameOID
            from cryptography.hazmat.primitives import serialization, hashes
            from cryptography.hazmat.primitives.asymmetric import rsa
            from cryptography.hazmat.backends import default_backend
            import datetime
            import base64


            # Generate private key
            private_key = rsa.generate_private_key(
                public_exponent=65537,
                key_size=2048,
                backend=default_backend()
            )
            public_key = private_key.public_key()

            # Create certificate subject and issuer (self-signed)
            subject = issuer = x509.Name([
                x509.NameAttribute(NameOID.COMMON_NAME, common_name)
            ])

            # Build self-signed certificate
            cert = (
                x509.CertificateBuilder()
                .subject_name(subject)
                .issuer_name(issuer)
                .public_key(public_key)
                .serial_number(x509.random_serial_number())
                .not_valid_before(datetime.datetime.utcnow())
                .not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(days=validity_days))
                .sign(private_key, hashes.SHA256(), default_backend())
            )

            # Encode private key and certificate to PEM format
            private_key_pem = private_key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.TraditionalOpenSSL,
                encryption_algorithm=serialization.NoEncryption()
            ).decode('utf-8')

            cert_pem = cert.public_bytes(encoding=serialization.Encoding.PEM).decode('utf-8')

            message += f"; TLS key pair generated with CN={common_name}, valid for {validity_days} days"
        except ImportError:
            return {
                'success': False,
                'updated': False,
                'message': f"Error: 'cryptography' library not installed. Install with 'pip install cryptography'; {message}"
            }
        except Exception as e:
            return {
                'success': False,
                'updated': False,
                'message': f"Failed to generate TLS key pair: {str(e)[:100]}...; {message}"
            }

        # Create Secret with TLS key pair
        try:
            secret_body = client.V1Secret(
                metadata=client.V1ObjectMeta(name=secret_name, namespace=namespace),
                data={
                    'tls.key': base64.b64encode(private_key_pem.encode('utf-8')).decode('utf-8'),
                    'tls.crt': base64.b64encode(cert_pem.encode('utf-8')).decode('utf-8')
                },
                type='kubernetes.io/tls'
            )
            core_v1_api.create_namespaced_secret(namespace=namespace, body=secret_body)
            updated = True
            message += f"; Secret {secret_name} created with TLS key pair"
        except ApiException as e:
            return {
                'success': False,
                'updated': False,
                'message': f"Failed to create Secret {secret_name}: Status: {e.status}, Reason: {e.reason}; Full Response Body: {str(e.body)[:500]}...; {message}"
            }

        return {
            'success': True,
            'updated': updated,
            'message': message
        }
    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"TLS Secret operation error for {secret_name}: {str(e)[:100]}..."
        }
def check_ironic_operator(namespace="ironic-standalone-operator-system", deployment_name="ironic-standalone-operator-controller-manager", timeout=60):
    """
    Check if the Ironic Operator is installed and available in Kubernetes by verifying the deployment status.
    This mimics the behavior of 'kubectl wait --for=condition=Available'.

    Args:
        namespace (str, optional): The namespace of the Ironic Operator deployment. Defaults to 'ironic-standalone-operator-system'.
        deployment_name (str, optional): The name of the Ironic Operator deployment. Defaults to 'ironic-standalone-operator-controller-manager'.
        timeout (int, optional): Maximum time in seconds to wait for the deployment to become available. Defaults to 60.

    Returns:
        dict: A dictionary with 'success' (bool), 'available' (bool), 'waited' (bool), 'transitioned' (bool), and 'message' (str).
    """
    try:
        import time

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        apps_v1_api = client.AppsV1Api()

        message = f"Checking Ironic Operator deployment {deployment_name} in namespace {namespace}"
        available = False
        initially_available = False
        waited = False
        transitioned = False

        # Check if deployment exists and get initial availability status
        try:
            status = apps_v1_api.read_namespaced_deployment_status(name=deployment_name, namespace=namespace)
            message += f"; Deployment {deployment_name} found"
            ready_replicas = status.status.ready_replicas or 0
            desired_replicas = status.spec.replicas
            initially_available = (ready_replicas == desired_replicas)
            if initially_available:
                message += f"; Deployment {deployment_name} is initially available"
        except ApiException as e:
            if e.status == 404:
                message += f"; Deployment {deployment_name} not found"
                return {
                    'success': False,
                    'available': False,
                    'waited': False,
                    'transitioned': False,
                    'message': message
                }
            else:
                message += f"; Error fetching deployment {deployment_name}: {str(e)[:100]}..."
                return {
                    'success': False,
                    'available': False,
                    'waited': False,
                    'transitioned': False,
                    'message': message
                }

        # If initially available, no need to wait
        if initially_available:
            return {
                'success': True,
                'available': True,
                'waited': False,
                'transitioned': False,
                'message': message
            }

        # Wait for deployment to become available (ready replicas match desired replicas)
        wait_time = 0
        wait_interval = 5  # Check every 5 seconds
        while wait_time < timeout:
            try:
                status = apps_v1_api.read_namespaced_deployment_status(name=deployment_name, namespace=namespace)
                ready_replicas = status.status.ready_replicas or 0
                desired_replicas = status.spec.replicas
                if ready_replicas == desired_replicas:
                    available = True
                    waited = True
                    transitioned = not initially_available
                    message += f"; Deployment {deployment_name} is available ({wait_time}s)"
                    break
            except ApiException as e:
                message += f"; Error checking deployment status: {str(e)[:100]}..."
                break
            time.sleep(wait_interval)
            wait_time += wait_interval

        if wait_time >= timeout and not available:
            message += f"; Timeout waiting for deployment {deployment_name} to become available ({timeout}s)"
            available = False
            waited = False
            transitioned = False

        return {
            'success': True if available else False,
            'available': available,
            'waited': waited,
            'transitioned': transitioned,
            'message': message
        }
    except Exception as e:
        return {
            'success': False,
            'available': False,
            'waited': False,
            'transitioned': False,
            'message': f"Error checking Ironic Operator: {str(e)[:100]}..."
        }
def ironic_instance_present(namespace, instance_name, database_secret_name="ironic-user", database_host="ironic-mariadb", database_port=3306, database_user="ironic", database_name="ironic", http_port=6385, networking_interface="", networking_ip="", networking_dhcp_range_start="", networking_dhcp_range_end="", networking_dhcp_range_gateway="", networking_dhcp_network_cidr="", networking_dhcp_serve_dns=False, networking_dhcp_dns_address="", inspection_dhcp_all_interfaces=False, enable_keepalived=False, keepalived_vip="", keepalived_interface="eth0", tls_secret_name="ironic-tls", ssh_public_key="", api_secret_name="ironic-api-creds", api_username="ironic", api_password=""):
    """
    Ensure that an Ironic instance is present in Kubernetes using the Ironic Standalone Operator.
    Creates or updates the Ironic Custom Resource with specified database connection, networking, and optional Keepalived settings, TLS, SSH key for deploy ramdisk, and API credentials.
    """
    try:
        updated = False
        api_secret_updated = False
        exists = False
        matches = False
        message = f"Configuring Ironic instance {instance_name} in namespace {namespace}"

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        core_v1_api = client.CoreV1Api()
        group = "ironic.metal3.io"
        version = "v1alpha1"
        plural = "ironics"

        # Step 1: Manage API credentials Secret
        api_secret_exists = False
        api_secret_matches = False
        try:
            api_secret = core_v1_api.read_namespaced_secret(name=api_secret_name, namespace=namespace)
            api_secret_exists = True
            current_username = api_secret.string_data.get('username', '') if api_secret.string_data else ''
            current_password = api_secret.string_data.get('password', '') if api_secret.string_data else ''
            if not current_username and api_secret.data:
                import base64
                current_username = base64.b64decode(api_secret.data.get('username', '')).decode('utf-8')
                current_password = base64.b64decode(api_secret.data.get('password', '')).decode('utf-8')
            if current_username != api_username or (api_password and current_password != api_password):
                api_secret_updated = True
            else:
                api_secret_matches = True
                api_secret_updated = False
        except ApiException as e:
            if e.status == 404:
                api_secret_exists = False
                api_secret_updated = True
            else:
                message += f"; Error fetching API Secret {api_secret_name}: {str(e)[:50]}..."
                return {
                    'success': False,
                    'updated': False,
                    'api_secret_updated': False,
                    'message': message
                }

        if not api_secret_exists or api_secret_updated:
            try:
                secret_body = client.V1Secret(
                    metadata=client.V1ObjectMeta(name=api_secret_name, namespace=namespace),
                    string_data={'username': api_username, 'password': api_password},
                    type='Opaque'
                )
                if api_secret_exists:
                    core_v1_api.replace_namespaced_secret(name=api_secret_name, namespace=namespace, body=secret_body)
                    api_secret_updated = True
                    message += f"; API Secret {api_secret_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(namespace=namespace, body=secret_body)
                    api_secret_updated = True
                    message += f"; API Secret {api_secret_name} created"
            except ApiException as e:
                message += f"; Failed to create/update API Secret {api_secret_name}: {str(e)[:50]}..."
                return {
                    'success': False,
                    'updated': False,
                    'api_secret_updated': False,
                    'message': message
                }
        else:
            message += f"; API Secret {api_secret_name} already up-to-date"

        # Step 2: Build desired spec for Ironic instance
        desired_spec = {
            "database": {
                "host": database_host,
                "name": database_name,
                "credentialsName": database_secret_name
            },
            "apiCredentialsName": api_secret_name,
            "networking": {
                "apiPort": int(http_port),
                "imageServerPort": 6180,
                "imageServerTLSPort": 6183
            },
            "inspection": {
                "dhcp": {
                    "allInterfaces": bool(inspection_dhcp_all_interfaces)
                }
            }
        }
        if networking_interface:
            desired_spec["networking"]["interface"] = networking_interface
        if networking_ip:
            desired_spec["networking"]["ipAddress"] = networking_ip
        if networking_dhcp_range_start and networking_dhcp_range_end and networking_dhcp_network_cidr:
            desired_spec["networking"]["dhcp"] = {
                "networkCIDR": networking_dhcp_network_cidr,
                "rangeBegin": networking_dhcp_range_start,
                "rangeEnd": networking_dhcp_range_end
            }
            if networking_dhcp_range_gateway:
                desired_spec["networking"]["dhcp"]["gatewayAddress"] = networking_dhcp_range_gateway
            desired_spec["networking"]["dhcp"]["serveDNS"] = bool(networking_dhcp_serve_dns)
            if networking_dhcp_dns_address and not networking_dhcp_serve_dns:
                desired_spec["networking"]["dhcp"]["dnsAddress"] = networking_dhcp_dns_address
        if enable_keepalived and keepalived_vip:
            desired_spec["networking"]["ipAddressManager"] = "keepalived"
            desired_spec["keepalived"] = {
                "enabled": True,
                "vip": keepalived_vip,
                "interface": keepalived_interface
            }
        if tls_secret_name:
            desired_spec["tls"] = {
                "certificateName": tls_secret_name
            }
        if ssh_public_key:
            desired_spec["deployRamdisk"] = {
                "sshKey": ssh_public_key
            }

        # Step 3: Check if Ironic instance exists and normalize current spec
        try:
            ironic = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=namespace, plural=plural, name=instance_name
            )
            exists = True
            current_spec = ironic.get('spec', {})
            current_resource_version = ironic.get('metadata', {}).get('resourceVersion', '')

            # Normalize current spec by adding missing fields with defaults matching desired spec
            def normalize_dict(desired, current):
                normalized = {}
                for key in desired:
                    if key in current:
                        if isinstance(desired[key], dict) and isinstance(current[key], dict):
                            normalized[key] = normalize_dict(desired[key], current[key])
                        else:
                            normalized[key] = current[key]
                            if key in ["apiPort", "imageServerPort", "imageServerTLSPort"] and isinstance(normalized[key], (int, float, str)):
                                try:
                                    normalized[key] = int(float(normalized[key]) if isinstance(normalized[key], str) else normalized[key])
                                except (ValueError, TypeError):
                                    pass
                            if key == "allInterfaces" and isinstance(normalized[key], (bool, str)):
                                normalized[key] = bool(normalized[key])
                            if key == "enabled" and isinstance(normalized[key], (bool, str)):
                                normalized[key] = bool(normalized[key])
                    else:
                        # Explicitly set defaults for missing fields based on desired spec
                        normalized[key] = desired[key]
                return normalized

            normalized_current_spec = normalize_dict(desired_spec, current_spec)
            # Compare fully normalized specs
            matches = normalized_current_spec == desired_spec
        except ApiException as e:
            if e.status == 404:
                exists = False
                matches = False
                message += f"; Ironic instance {instance_name} not found, will create"
            else:
                return {
                    'success': False,
                    'updated': False,
                    'api_secret_updated': api_secret_updated,
                    'message': f"Error fetching Ironic instance {instance_name}: {str(e)[:100]}...; {message}"
                }

        # Build the full Ironic body for create/update
        ironic_body = {
            "apiVersion": f"{group}/{version}",
            "kind": "Ironic",
            "metadata": {
                "name": instance_name,
                "namespace": namespace
            },
            "spec": {
                "database": {
                    "host": database_host,
                    "port": int(database_port),
                    "name": database_name,
                    "user": database_user,
                    "credentialsName": database_secret_name
                },
                "apiCredentialsName": api_secret_name,
                "networking": {
                    "apiPort": int(http_port),
                    "imageServerPort": 6180,
                    "imageServerTLSPort": 6183
                },
                "inspection": {
                    "dhcp": {
                        "allInterfaces": bool(inspection_dhcp_all_interfaces)
                    }
                }
            }
        }
        if networking_interface:
            ironic_body["spec"]["networking"]["interface"] = networking_interface
        if networking_ip:
            ironic_body["spec"]["networking"]["ipAddress"] = networking_ip
        if networking_dhcp_range_start and networking_dhcp_range_end and networking_dhcp_network_cidr:
            ironic_body["spec"]["networking"]["dhcp"] = {
                "networkCIDR": networking_dhcp_network_cidr,
                "rangeBegin": networking_dhcp_range_start,
                "rangeEnd": networking_dhcp_range_end
            }
            if networking_dhcp_range_gateway:
                ironic_body["spec"]["networking"]["dhcp"]["gatewayAddress"] = networking_dhcp_range_gateway
            ironic_body["spec"]["networking"]["dhcp"]["serveDNS"] = bool(networking_dhcp_serve_dns)
            if networking_dhcp_dns_address and not networking_dhcp_serve_dns:
                ironic_body["spec"]["networking"]["dhcp"]["dnsAddress"] = networking_dhcp_dns_address
        if enable_keepalived and keepalived_vip:
            ironic_body["spec"]["networking"]["ipAddressManager"] = "keepalived"
            ironic_body["spec"]["keepalived"] = {
                "enabled": True,
                "vip": keepalived_vip,
                "interface": keepalived_interface
            }
        if tls_secret_name:
            ironic_body["spec"]["tls"] = {
                "certificateName": tls_secret_name
            }
        if ssh_public_key:
            ironic_body["spec"]["deployRamdisk"] = {
                "sshKey": ssh_public_key
            }

        # Create or update Ironic instance if necessary
        if not exists or not matches:
            try:
                if exists:
                    if 'metadata' in ironic and 'resourceVersion' in ironic['metadata']:
                        ironic_body['metadata']['resourceVersion'] = ironic['metadata']['resourceVersion']
                    custom_api.replace_namespaced_custom_object(
                        group=group, version=version, namespace=namespace, plural=plural, name=instance_name, body=ironic_body
                    )
                    updated = True
                    message += f"; Ironic instance {instance_name} updated"
                else:
                    custom_api.create_namespaced_custom_object(
                        group=group, version=version, namespace=namespace, plural=plural, body=ironic_body
                    )
                    updated = True
                    message += f"; Ironic instance {instance_name} created"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'api_secret_updated': api_secret_updated,
                    'message': f"Failed to create/update Ironic instance {instance_name}: Status: {e.status if hasattr(e, 'status') else 'Unknown'}, Reason: {e.reason if hasattr(e, 'reason') else 'Unknown'}; {message}"
                }
        else:
            message += f"; Ironic instance {instance_name} already up-to-date"
            updated = False

        return {
            'success': True if updated or matches else False,
            'updated': updated,
            'api_secret_updated': api_secret_updated,
            'message': message
        }
    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'api_secret_updated': False,
            'message': f"Ironic instance operation error for {instance_name}: {str(e)[:100]}..."
        }
def image_server_present(namespace, deployment_name="ironic-image-server", service_name="ironic-image-server", image="python:3.9-slim", port=6180, tls_port=6183, storage_path="/images", pvc_name="ironic-images-pvc", storage_size="10Gi", storage_class="local-storage", service_type="ClusterIP", external_ip=None):
    """
    Ensure that an image server for Ironic is present in Kubernetes.
    Creates or updates a Deployment and Service to serve images over HTTP for bare metal provisioning.
    Also ensures a PersistentVolumeClaim (PVC) for storing images. Optionally configures the Service for external access.

    Args:
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
        external_ip (str, optional): An external IP to assign to the Service if supported by the cluster (used with service_type 'ClusterIP' or 'LoadBalancer'). Defaults to None.

    Returns:
        dict: A dictionary with 'success' (bool), 'deployment_updated' (bool), 'service_updated' (bool), 'pvc_updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.image_server_present baremetal-operator-system service_type=LoadBalancer external_ip=192.168.1.100
    """
    try:
        deployment_updated = False
        service_updated = False
        pvc_updated = False
        deployment_exists = False
        service_exists = False
        pvc_exists = False
        deployment_matches = False
        service_matches = False
        pvc_matches = False
        message = f"Configuring Ironic image server in namespace {namespace}"

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()
        apps_v1_api = client.AppsV1Api()

        # Step 1: Check if PVC exists
        try:
            pvc = core_v1_api.read_namespaced_persistent_volume_claim(name=pvc_name, namespace=namespace)
            pvc_exists = True
            current_pvc_spec = pvc.spec
            if (current_pvc_spec.resources.requests.get('storage', '') != storage_size or
                current_pvc_spec.storage_class_name != storage_class):
                pvc_matches = False
            else:
                pvc_matches = True
        except ApiException as e:
            if e.status == 404:
                pvc_exists = False
                pvc_matches = False
            else:
                return {
                    'success': False,
                    'deployment_updated': False,
                    'service_updated': False,
                    'pvc_updated': False,
                    'message': f"Error fetching PVC {pvc_name}: {str(e)[:100]}...; {message}"
                }

        # Step 2: Create or update PVC if necessary
        if not pvc_exists or not pvc_matches:
            try:
                pvc_body = client.V1PersistentVolumeClaim(
                    metadata=client.V1ObjectMeta(name=pvc_name, namespace=namespace),
                    spec=client.V1PersistentVolumeClaimSpec(
                        access_modes=["ReadWriteOnce"],
                        resources=client.V1ResourceRequirements(
                            requests={'storage': storage_size}
                        ),
                        storage_class_name=storage_class
                    )
                )
                if pvc_exists:
                    core_v1_api.replace_namespaced_persistent_volume_claim(name=pvc_name, namespace=namespace, body=pvc_body)
                    pvc_updated = True
                    message += f"; PVC {pvc_name} updated"
                else:
                    core_v1_api.create_namespaced_persistent_volume_claim(namespace=namespace, body=pvc_body)
                    pvc_updated = True
                    message += f"; PVC {pvc_name} created"
            except ApiException as e:
                return {
                    'success': False,
                    'deployment_updated': False,
                    'service_updated': False,
                    'pvc_updated': False,
                    'message': f"Failed to create/update PVC {pvc_name}: {str(e)[:100]}...; {message}"
                }
        else:
            message += f"; PVC {pvc_name} already up-to-date"

        # Step 3: Check if Deployment exists
        try:
            deployment = apps_v1_api.read_namespaced_deployment(name=deployment_name, namespace=namespace)
            deployment_exists = True
            current_deployment_spec = deployment.spec
            current_image = current_deployment_spec.template.spec.containers[0].image if current_deployment_spec.template.spec.containers else ''
            current_command = current_deployment_spec.template.spec.containers[0].command if current_deployment_spec.template.spec.containers else []
            if (current_image != image or
                current_command != ["python", "-m", "http.server", str(port), "--directory", storage_path]):
                deployment_matches = False
            else:
                deployment_matches = True
        except ApiException as e:
            if e.status == 404:
                deployment_exists = False
                deployment_matches = False
            else:
                return {
                    'success': False,
                    'deployment_updated': False,
                    'service_updated': False,
                    'pvc_updated': pvc_updated,
                    'message': f"Error fetching Deployment {deployment_name}: {str(e)[:100]}...; {message}"
                }

        # Step 4: Create or update Deployment if necessary
        if not deployment_exists or not deployment_matches:
            try:
                deployment_body = client.V1Deployment(
                    metadata=client.V1ObjectMeta(name=deployment_name, namespace=namespace),
                    spec=client.V1DeploymentSpec(
                        replicas=1,
                        selector=client.V1LabelSelector(match_labels={"app": "ironic-image-server"}),
                        template=client.V1PodTemplateSpec(
                            metadata=client.V1ObjectMeta(labels={"app": "ironic-image-server"}),
                            spec=client.V1PodSpec(
                                containers=[
                                    client.V1Container(
                                        name="image-server",
                                        image=image,
                                        command=["python", "-m", "http.server", str(port), "--directory", storage_path],
                                        ports=[client.V1ContainerPort(container_port=port)],
                                        volume_mounts=[client.V1VolumeMount(name="images", mount_path=storage_path)]
                                    )
                                ],
                                volumes=[
                                    client.V1Volume(
                                        name="images",
                                        persistent_volume_claim=client.V1PersistentVolumeClaimVolumeSource(claim_name=pvc_name)
                                    )
                                ]
                            )
                        )
                    )
                )
                if deployment_exists:
                    apps_v1_api.replace_namespaced_deployment(name=deployment_name, namespace=namespace, body=deployment_body)
                    deployment_updated = True
                    message += f"; Deployment {deployment_name} updated"
                else:
                    apps_v1_api.create_namespaced_deployment(namespace=namespace, body=deployment_body)
                    deployment_updated = True
                    message += f"; Deployment {deployment_name} created"
            except ApiException as e:
                return {
                    'success': False,
                    'deployment_updated': False,
                    'service_updated': False,
                    'pvc_updated': pvc_updated,
                    'message': f"Failed to create/update Deployment {deployment_name}: {str(e)[:100]}...; {message}"
                }
        else:
            message += f"; Deployment {deployment_name} already up-to-date"

        # Step 5: Check if Service exists
        try:
            service = core_v1_api.read_namespaced_service(name=service_name, namespace=namespace)
            service_exists = True
            current_service_spec = service.spec
            current_ports = current_service_spec.ports if current_service_spec.ports else []
            current_type = current_service_spec.type if current_service_spec.type else "ClusterIP"
            current_external_ips = current_service_spec.external_i_ps if hasattr(current_service_spec, 'external_i_ps') else []
            if (len(current_ports) != 1 or 
                current_ports[0].port != port or 
                current_ports[0].target_port != port or
                current_type != service_type or
                (external_ip and current_external_ips != [external_ip])):
                service_matches = False
            else:
                service_matches = True
        except ApiException as e:
            if e.status == 404:
                service_exists = False
                service_matches = False
            else:
                return {
                    'success': False,
                    'deployment_updated': deployment_updated,
                    'service_updated': False,
                    'pvc_updated': pvc_updated,
                    'message': f"Error fetching Service {service_name}: {str(e)[:100]}...; {message}"
                }

        # Step 6: Create or update Service if necessary
        if not service_exists or not service_matches:
            try:
                service_body = client.V1Service(
                    metadata=client.V1ObjectMeta(name=service_name, namespace=namespace),
                    spec=client.V1ServiceSpec(
                        selector={"app": "ironic-image-server"},
                        ports=[client.V1ServicePort(port=port, target_port=port, protocol="TCP")],
                        type=service_type
                    )
                )
                if external_ip and service_type in ["ClusterIP", "LoadBalancer"]:
                    service_body.spec.external_i_ps = [external_ip]
                    message += f"; Service {service_name} configured with external IP {external_ip}"
                if service_exists:
                    core_v1_api.replace_namespaced_service(name=service_name, namespace=namespace, body=service_body)
                    service_updated = True
                    message += f"; Service {service_name} updated"
                else:
                    core_v1_api.create_namespaced_service(namespace=namespace, body=service_body)
                    service_updated = True
                    message += f"; Service {service_name} created"
            except ApiException as e:
                return {
                    'success': False,
                    'deployment_updated': deployment_updated,
                    'service_updated': False,
                    'pvc_updated': pvc_updated,
                    'message': f"Failed to create/update Service {service_name}: {str(e)[:100]}...; {message}"
                }
        else:
            message += f"; Service {service_name} already up-to-date"

        return {
            'success': True if (deployment_updated or service_updated or pvc_updated or (deployment_matches and service_matches and pvc_matches)) else False,
            'deployment_updated': deployment_updated,
            'service_updated': service_updated,
            'pvc_updated': pvc_updated,
            'message': message
        }
    except Exception as e:
        return {
            'success': False,
            'deployment_updated': False,
            'service_updated': False,
            'pvc_updated': False,
            'message': f"Image server operation error: {str(e)[:100]}..."
        }
def bmh_state(namespace, bmh_name, desired_state):
    """
    Check if a Bare Metal Host (BMH) object in Kubernetes is in the specified state.

    Args:
        namespace (str): The namespace of the Bare Metal Host resource in Kubernetes.
        bmh_name (str): The name of the Bare Metal Host resource.
        desired_state (str): The state to check for (e.g., 'provisioned', 'ready', 'error').

    Returns:
        dict: A dictionary with 'success' (bool), 'in_state' (bool), 'current_state' (str), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.bmh_state baremetal-operator-system compute-133-26 provisioned
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        group = "metal3.io"
        version = "v1alpha1"
        plural = "baremetalhosts"

        # Check BMH status
        resource = custom_api.get_namespaced_custom_object(
            group=group, version=version, namespace=namespace, plural=plural, name=bmh_name
        )
        status = resource.get('status', {})
        current_state = status.get('provisioning', {}).get('state', 'unknown')

        return {
            'success': True,
            'in_state': current_state == desired_state,
            'current_state': current_state,
            'message': f"BMH {bmh_name} is in state: {current_state}. Checking for: {desired_state}"
        }

    except ApiException as e:
        if e.status == 404:
            return {
                'success': False,
                'in_state': False,
                'current_state': 'not_found',
                'message': f"BMH {bmh_name} not found in namespace {namespace}"
            }
        return {
            'success': False,
            'in_state': False,
            'current_state': 'error',
            'message': f"Kubernetes API error: {str(e)[:50]}..."
        }
    except Exception as e:
        return {
            'success': False,
            'in_state': False,
            'current_state': 'error',
            'message': f"Error checking BMH state: {str(e)[:50]}..."
        }
def namespace_present(namespace):
    """
    Ensure that a Kubernetes namespace exists. If it does not exist, create it.

    Args:
        namespace (str): The name of the namespace to ensure exists.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.namespace_present my-namespace
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()
        exists = False
        updated = False

        # Check if namespace exists
        try:
            core_v1_api.read_namespace(name=namespace)
            exists = True
            message = f"Namespace {namespace} already exists"
        except ApiException as e:
            if e.status == 404:
                exists = False
            else:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Error checking namespace {namespace}: {str(e)[:50]}..."
                }

        # Create namespace if it does not exist
        if not exists:
            try:
                namespace_body = client.V1Namespace(
                    metadata=client.V1ObjectMeta(name=namespace)
                )
                core_v1_api.create_namespace(body=namespace_body)
                updated = True
                message = f"Namespace {namespace} created"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to create namespace {namespace}: {str(e)[:50]}..."
                }

        return {
            'success': True,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Namespace operation error: {str(e)[:50]}..."
        }
def ceph_cluster_present(namespace, cluster_name, spec):
    """
    Ensure that a CephCluster Custom Resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    Args:
        namespace (str): The namespace for the CephCluster resource.
        cluster_name (str): The name of the CephCluster resource.
        spec (dict): The specification for the CephCluster resource, including settings like cephVersion, storage, etc.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.ceph_cluster_present rook-ceph rook-ceph spec_dict
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        group = "ceph.rook.io"
        version = "v1"
        plural = "cephclusters"

        exists = False
        updated = False
        matches = False

        # Check if CephCluster exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=namespace, plural=plural, name=cluster_name
            )
            exists = True
            current_spec = resource.get('spec', {})
            # Simple check for spec equality (deep comparison could be added if needed)
            if current_spec == spec:
                matches = True
                message = f"CephCluster {cluster_name} in namespace {namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"CephCluster {cluster_name} in namespace {namespace} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"CephCluster {cluster_name} in namespace {namespace} does not exist"
            else:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Error checking CephCluster {cluster_name}: {str(e)[:50]}..."
                }

        # Create or update CephCluster
        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "CephCluster",
            "metadata": {
                "name": cluster_name,
                "namespace": namespace
            },
            "spec": spec
        }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group, version=version, namespace=namespace, plural=plural, body=body
                )
                updated = True
                message = f"CephCluster {cluster_name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to create CephCluster {cluster_name}: {str(e)[:50]}..."
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if 'metadata' in resource and 'resourceVersion' in resource['metadata']:
                    body['metadata']['resourceVersion'] = resource['metadata']['resourceVersion']
                custom_api.replace_namespaced_custom_object(
                    group=group, version=version, namespace=namespace, plural=plural, name=cluster_name, body=body
                )
                updated = True
                message = f"CephCluster {cluster_name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to update CephCluster {cluster_name}: {str(e)[:50]}..."
                }
        return {
            'success': True,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"CephCluster operation error: {str(e)[:50]}..."
        }
def configmap_present(namespace, name, data, labels=None, annotations=None):
    """
    Ensure that a Kubernetes ConfigMap exists in the specified namespace. If it does not exist, create it.
    If it exists, update it if the data, labels, or annotations differ.

    Args:
        namespace (str): The namespace for the ConfigMap.
        name (str): The name of the ConfigMap.
        data (dict): The data to store in the ConfigMap (key-value pairs).
        labels (dict, optional): Labels to apply to the ConfigMap. Defaults to None.
        annotations (dict, optional): Annotations to apply to the ConfigMap. Defaults to None.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.configmap_present efk opensearch-dashboards-config "{'opensearch_dashboards.yml': 'content'}"
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()
        exists = False
        updated = False
        matches = False

        # Check if ConfigMap exists
        try:
            configmap = core_v1_api.read_namespaced_config_map(name=name, namespace=namespace)
            exists = True
            current_data = configmap.data or {}
            current_labels = configmap.metadata.labels or {}
            current_annotations = configmap.metadata.annotations or {}

            # Check if data, labels, or annotations match
            desired_labels = labels or {}
            desired_annotations = annotations or {}
            if (current_data == data and
                current_labels == desired_labels and
                current_annotations == desired_annotations):
                matches = True
                message = f"ConfigMap {name} in namespace {namespace} already exists and matches desired state"
            else:
                matches = False
                message = f"ConfigMap {name} in namespace {namespace} exists but content differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"ConfigMap {name} in namespace {namespace} does not exist"
            else:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Error checking ConfigMap {name}: {str(e)[:50]}..."
                }

        # Create or update ConfigMap
        configmap_body = client.V1ConfigMap(
            metadata=client.V1ObjectMeta(
                name=name,
                namespace=namespace,
                labels=labels or {},
                annotations=annotations or {}
            ),
            data=data
        )

        if not exists:
            try:
                core_v1_api.create_namespaced_config_map(namespace=namespace, body=configmap_body)
                updated = True
                message = f"ConfigMap {name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to create ConfigMap {name}: {str(e)[:50]}..."
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if exists and hasattr(configmap, 'metadata') and hasattr(configmap.metadata, 'resource_version'):
                    configmap_body.metadata.resource_version = configmap.metadata.resource_version
                core_v1_api.replace_namespaced_config_map(name=name, namespace=namespace, body=configmap_body)
                updated = True
                message = f"ConfigMap {name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to update ConfigMap {name}: {str(e)[:50]}..."
                }

        return {
            'success': True,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"ConfigMap operation error: {str(e)[:50]}..."
        }
def service_present(namespace, service_name, service_type="LoadBalancer", selector=None, ports=None, annotations=None, external_ip=None):
    """
    Ensure that a Kubernetes Service is present in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    Args:
        namespace (str): The namespace for the Service.
        service_name (str): The name of the Service.
        service_type (str, optional): The type of Service ('ClusterIP', 'NodePort', 'LoadBalancer'). Defaults to 'LoadBalancer'.
        selector (dict, optional): The selector labels to match target pods. Defaults to None.
        ports (list, optional): List of port mappings (each with 'name', 'port', 'targetPort', 'protocol'). Defaults to None.
        annotations (dict, optional): Annotations to apply to the Service (e.g., for MetalLB). Defaults to None.
        external_ip (str, optional): An external IP to assign to the Service if supported. Defaults to None.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.service_present openstack openstack-public service_type=LoadBalancer selector="{'app.kubernetes.io/name': 'ingress-nginx'}" ports="[{ 'name': 'http', 'port': 80, 'targetPort': 80, 'protocol': 'TCP' }]" annotations="{'metallb.universe.tf/address-pool': 'default'}"
    """
    try:
        try:
            config.load_incluster_config()
            message = f"Loaded in-cluster config for Service {service_name} in namespace {namespace}"
        except config.ConfigException:
            config.load_kube_config()
            message = f"Loaded kubeconfig for Service {service_name} in namespace {namespace}"

        core_v1_api = client.CoreV1Api()
        exists = False
        updated = False
        matches = False

        # Default ports if none provided
        if ports is None:
            ports = [
                {'name': 'http', 'port': 80, 'targetPort': 80, 'protocol': 'TCP'},
                {'name': 'https', 'port': 443, 'targetPort': 443, 'protocol': 'TCP'}
            ]

        message += f"; Configuring as type {service_type}"

        # Check if Service exists
        try:
            service = core_v1_api.read_namespaced_service(name=service_name, namespace=namespace)
            exists = True
            current_spec = service.spec
            current_annotations = service.metadata.annotations or {}
            desired_annotations = annotations or {}
            desired_selector = selector or {}
            current_selector = current_spec.selector or {}
            desired_ports = ports
            current_ports = current_spec.ports if current_spec.ports else []
            current_type = current_spec.type if current_spec.type else "ClusterIP"
            current_external_ips = current_spec.external_i_ps if hasattr(current_spec, 'external_i_ps') else []

            # Normalize ports for comparison (convert target_port to int if possible)
            normalized_current_ports = []
            for p in current_ports:
                port_dict = {
                    'name': p.name if p.name else '',
                    'port': p.port,
                    'targetPort': int(p.target_port) if isinstance(p.target_port, (int, str)) and str(p.target_port).isdigit() else p.target_port,
                    'protocol': p.protocol if p.protocol else 'TCP'
                }
                normalized_current_ports.append(port_dict)

            normalized_desired_ports = []
            for p in desired_ports:
                port_dict = {
                    'name': p.get('name', ''),
                    'port': p['port'],
                    'targetPort': int(p['targetPort']) if isinstance(p['targetPort'], str) and p['targetPort'].isdigit() else p['targetPort'],
                    'protocol': p.get('protocol', 'TCP')
                }
                normalized_desired_ports.append(port_dict)

            # Check if spec and annotations match
            if (current_type == service_type and
                current_selector == desired_selector and
                normalized_current_ports == normalized_desired_ports and
                current_annotations == desired_annotations and
                (not external_ip or current_external_ips == [external_ip])):
                matches = True
                message += f"; Service {service_name} already up-to-date"
            else:
                matches = False
                message += f"; Service {service_name} exists but spec or annotations differ (Type: {current_type} vs {service_type}, Selector: {current_selector} vs {desired_selector}, Ports: {normalized_current_ports} vs {normalized_desired_ports}, Annotations: {current_annotations} vs {desired_annotations}, External IP: {current_external_ips} vs {[external_ip] if external_ip else []})"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message += f"; Service {service_name} does not exist, will create"
            else:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Error fetching Service {service_name}: Status: {e.status if hasattr(e, 'status') else 'Unknown'}, Reason: {e.reason if hasattr(e, 'reason') else 'Unknown'}, Body: {str(e.body)[:200] if hasattr(e, 'body') else 'N/A'}...; {message}"
                }

        # Build Service spec
        service_spec = client.V1ServiceSpec(
            selector=selector if selector else {},
            type=service_type,
            ports=[client.V1ServicePort(
                name=p.get('name', ''),
                port=p['port'],
                target_port=p['targetPort'],
                protocol=p.get('protocol', 'TCP')
            ) for p in ports]
        )
        if external_ip and service_type in ["ClusterIP", "LoadBalancer"]:
            service_spec.external_i_ps = [external_ip]
            message += f"; Configured with external IP {external_ip}"

        service_body = client.V1Service(
            metadata=client.V1ObjectMeta(
                name=service_name,
                namespace=namespace,
                annotations=annotations if annotations else {}
            ),
            spec=service_spec
        )

        # Create or update Service if necessary
        if not exists:
            try:
                core_v1_api.create_namespaced_service(namespace=namespace, body=service_body)
                updated = True
                message += f"; Service {service_name} created"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to create Service {service_name}: Status: {e.status if hasattr(e, 'status') else 'Unknown'}, Reason: {e.reason if hasattr(e, 'reason') else 'Unknown'}, Body: {str(e.body)[:200] if hasattr(e, 'body') else 'N/A'}...; {message}"
                }
        elif not matches:
            try:
                core_v1_api.replace_namespaced_service(name=service_name, namespace=namespace, body=service_body)
                updated = True
                message += f"; Service {service_name} updated"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to update Service {service_name}: Status: {e.status if hasattr(e, 'status') else 'Unknown'}, Reason: {e.reason if hasattr(e, 'reason') else 'Unknown'}, Body: {str(e.body)[:200] if hasattr(e, 'body') else 'N/A'}...; {message}"
                }
        return {
            'success': True,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Service operation error for {service_name}: {str(e)[:200]}..."
        }
    return ret
def node_label_present(namespace, node_name, labels):
    """
    Ensure that the specified labels are present on a Kubernetes node.
    If a label key exists with a different value, it will be updated. If it doesn't exist, it will be added.

    Args:
        namespace (str): The namespace is not used for node operations but kept for consistency.
        node_name (str): The name of the node to apply labels to.
        labels (dict): A dictionary of key-value pairs representing the labels to apply.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'message' (str), and 'changes' (dict).

    CLI Example:
        salt '*' kinetic-k8s.node_label_present unused-namespace k8s-node-1 "{'key1': 'value1', 'key2': 'value2'}"
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()
        updated = False
        changes = {}

        # Retrieve the current node object
        node = core_v1_api.read_node(name=node_name)
        current_labels = node.metadata.labels or {}

        # Determine labels to update or add
        labels_to_apply = {}
        for key, value in labels.items():
            if key not in current_labels or current_labels[key] != value:
                labels_to_apply[key] = value
                changes[key] = {'old': current_labels.get(key, 'not set'), 'new': value}

        if labels_to_apply:
            # Update the node labels
            node.metadata.labels.update(labels_to_apply)
            core_v1_api.replace_node(name=node_name, body=node)
            updated = True
            message = f"Labels updated on node {node_name}"
        else:
            message = f"All specified labels already present on node {node_name}"

        return {
            'success': True,
            'updated': updated,
            'message': message,
            'changes': changes
        }

    except ApiException as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Kubernetes API error while updating labels on node {node_name}: {str(e)[:50]}...",
            'changes': {}
        }
    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Error updating labels on node {node_name}: {str(e)[:50]}...",
            'changes': {}
        }
def metallb_pool_present(namespace, pool_name, addresses, metallb_namespace="metallb-system"):
    """
    Ensure that a MetalLB IPAddressPool Custom Resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    Args:
        namespace (str): The namespace for the IPAddressPool resource (unused, kept for consistency).
        pool_name (str): The name of the IPAddressPool resource.
        addresses (list): List of IP address ranges (e.g., ["10.150.1.43-10.150.1.50"]).
        metallb_namespace (str, optional): The namespace where MetalLB is installed. Defaults to 'metallb-system'.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.metallb_pool_present unused-namespace default ["10.150.1.43-10.150.1.50"]
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        group = "metallb.io"
        version = "v1beta1"
        plural = "ipaddresspools"

        exists = False
        updated = False
        matches = False

        # Check if IPAddressPool exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=metallb_namespace, plural=plural, name=pool_name
            )
            exists = True
            current_addresses = resource.get('spec', {}).get('addresses', [])
            if current_addresses == addresses:
                matches = True
                message = f"IPAddressPool {pool_name} in namespace {metallb_namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"IPAddressPool {pool_name} in namespace {metallb_namespace} exists but addresses differ"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"IPAddressPool {pool_name} in namespace {metallb_namespace} does not exist"
            else:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Error checking IPAddressPool {pool_name}: {str(e)[:50]}..."
                }

        # Create or update IPAddressPool
        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "IPAddressPool",
            "metadata": {
                "name": pool_name,
                "namespace": metallb_namespace
            },
            "spec": {
                "addresses": addresses
            }
        }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group, version=version, namespace=metallb_namespace, plural=plural, body=body
                )
                updated = True
                message = f"IPAddressPool {pool_name} created in namespace {metallb_namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to create IPAddressPool {pool_name}: {str(e)[:50]}..."
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if 'metadata' in resource and 'resourceVersion' in resource['metadata']:
                    body['metadata']['resourceVersion'] = resource['metadata']['resourceVersion']
                custom_api.replace_namespaced_custom_object(
                    group=group, version=version, namespace=metallb_namespace, plural=plural, name=pool_name, body=body
                )
                updated = True
                message = f"IPAddressPool {pool_name} updated in namespace {metallb_namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to update IPAddressPool {pool_name}: {str(e)[:50]}..."
                }
        return {
            'success': True,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"IPAddressPool operation error: {str(e)[:50]}..."
        }

def metallb_l2_advertisement_present(namespace, advertisement_name, pool_names, metallb_namespace="metallb-system"):
    """
    Ensure that a MetalLB L2Advertisement Custom Resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    Args:
        namespace (str): The namespace for the L2Advertisement resource (unused, kept for consistency).
        advertisement_name (str): The name of the L2Advertisement resource.
        pool_names (list): List of IPAddressPool names to advertise.
        metallb_namespace (str, optional): The namespace where MetalLB is installed. Defaults to 'metallb-system'.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.metallb_l2_advertisement_present unused-namespace default-l2 ["default"]
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        group = "metallb.io"
        version = "v1beta1"
        plural = "l2advertisements"

        exists = False
        updated = False
        matches = False

        # Check if L2Advertisement exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=metallb_namespace, plural=plural, name=advertisement_name
            )
            exists = True
            current_pools = resource.get('spec', {}).get('ipAddressPools', [])
            if current_pools == pool_names:
                matches = True
                message = f"L2Advertisement {advertisement_name} in namespace {metallb_namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"L2Advertisement {advertisement_name} in namespace {metallb_namespace} exists but pools differ"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"L2Advertisement {advertisement_name} in namespace {metallb_namespace} does not exist"
            else:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Error checking L2Advertisement {advertisement_name}: {str(e)[:50]}..."
                }

        # Create or update L2Advertisement
        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "L2Advertisement",
            "metadata": {
                "name": advertisement_name,
                "namespace": metallb_namespace
            },
            "spec": {
                "ipAddressPools": pool_names
            }
        }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group, version=version, namespace=metallb_namespace, plural=plural, body=body
                )
                updated = True
                message = f"L2Advertisement {advertisement_name} created in namespace {metallb_namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to create L2Advertisement {advertisement_name}: {str(e)[:50]}..."
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if 'metadata' in resource and 'resourceVersion' in resource['metadata']:
                    body['metadata']['resourceVersion'] = resource['metadata']['resourceVersion']
                custom_api.replace_namespaced_custom_object(
                    group=group, version=version, namespace=metallb_namespace, plural=plural, name=advertisement_name, body=body
                )
                updated = True
                message = f"L2Advertisement {advertisement_name} updated in namespace {metallb_namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to update L2Advertisement {advertisement_name}: {str(e)[:50]}..."
                }
        return {
            'success': True,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"L2Advertisement operation error: {str(e)[:50]}..."
        }
def certmanager_issuer_present(namespace, issuer_name, issuer_kind="Issuer", spec=None):
    """
    Ensure that a Cert-Manager Issuer or ClusterIssuer resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    Args:
        namespace (str): The namespace for the Issuer resource. Use 'cluster-wide' for ClusterIssuer.
        issuer_name (str): The name of the Issuer or ClusterIssuer resource.
        issuer_kind (str, optional): The kind of issuer, either 'Issuer' or 'ClusterIssuer'. Defaults to 'Issuer'.
        spec (dict, optional): The specification for the Issuer resource. If not provided, a basic self-signed issuer spec will be used.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.certmanager_issuer_present cert-manager my-issuer spec_dict
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        group = "cert-manager.io"
        version = "v1"
        plural = "issuers" if issuer_kind == "Issuer" else "clusterissuers"

        exists = False
        updated = False
        matches = False

        # Default spec for a self-signed issuer if none provided
        if spec is None:
            spec = {
                "selfSigned": {}
            }

        # Check if Issuer/ClusterIssuer exists
        try:
            if issuer_kind == "Issuer":
                resource = custom_api.get_namespaced_custom_object(
                    group=group, version=version, namespace=namespace, plural=plural, name=issuer_name
                )
            else:
                resource = custom_api.get_cluster_custom_object(
                    group=group, version=version, plural=plural, name=issuer_name
                )
            exists = True
            current_spec = resource.get('spec', {})
            if current_spec == spec:
                matches = True
                message = f"{issuer_kind} {issuer_name} already exists and matches desired spec in {namespace if issuer_kind == 'Issuer' else 'cluster-wide'}"
            else:
                matches = False
                message = f"{issuer_kind} {issuer_name} exists but spec differs in {namespace if issuer_kind == 'Issuer' else 'cluster-wide'}"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"{issuer_kind} {issuer_name} does not exist in {namespace if issuer_kind == 'Issuer' else 'cluster-wide'}"
            else:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Error checking {issuer_kind} {issuer_name}: {str(e)[:50]}..."
                }

        # Create or update Issuer/ClusterIssuer
        body = {
            "apiVersion": f"{group}/{version}",
            "kind": issuer_kind,
            "metadata": {
                "name": issuer_name
            },
            "spec": spec
        }
        if issuer_kind == "Issuer":
            body["metadata"]["namespace"] = namespace

        if not exists:
            try:
                if issuer_kind == "Issuer":
                    custom_api.create_namespaced_custom_object(
                        group=group, version=version, namespace=namespace, plural=plural, body=body
                    )
                else:
                    custom_api.create_cluster_custom_object(
                        group=group, version=version, plural=plural, body=body
                    )
                updated = True
                message = f"{issuer_kind} {issuer_name} created in {namespace if issuer_kind == 'Issuer' else 'cluster-wide'}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to create {issuer_kind} {issuer_name}: {str(e)[:50]}..."
                }
        elif not matches:
            try:
                if 'metadata' in resource and 'resourceVersion' in resource['metadata']:
                    body['metadata']['resourceVersion'] = resource['metadata']['resourceVersion']
                if issuer_kind == "Issuer":
                    custom_api.replace_namespaced_custom_object(
                        group=group, version=version, namespace=namespace, plural=plural, name=issuer_name, body=body
                    )
                else:
                    custom_api.replace_cluster_custom_object(
                        group=group, version=version, plural=plural, name=issuer_name, body=body
                    )
                updated = True
                message = f"{issuer_kind} {issuer_name} updated in {namespace if issuer_kind == 'Issuer' else 'cluster-wide'}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to update {issuer_kind} {issuer_name}: {str(e)[:50]}..."
                }
        return {
            'success': True,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"{issuer_kind} operation error: {str(e)[:50]}..."
        }

def ingress_present(namespace, ingress_name, spec, annotations=None):
    """
    Ensure that a Kubernetes Ingress resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    Args:
        namespace (str): The namespace for the Ingress resource.
        ingress_name (str): The name of the Ingress resource.
        spec (dict): The specification for the Ingress resource, including rules, tls, etc.
        annotations (dict, optional): Annotations to apply to the Ingress (e.g., for ingress controller settings). Defaults to None.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.ingress_present openstack my-ingress spec_dict annotations_dict
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        networking_v1_api = client.NetworkingV1Api()
        exists = False
        updated = False
        matches = False

        # Check if Ingress exists
        try:
            ingress = networking_v1_api.read_namespaced_ingress(name=ingress_name, namespace=namespace)
            exists = True
            current_spec = ingress.spec.to_dict() if ingress.spec else {}
            current_annotations = ingress.metadata.annotations or {}
            desired_annotations = annotations or {}
            desired_spec = spec

            # Check if spec and annotations match
            if current_spec == desired_spec and current_annotations == desired_annotations:
                matches = True
                message = f"Ingress {ingress_name} in namespace {namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"Ingress {ingress_name} in namespace {namespace} exists but spec or annotations differ"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"Ingress {ingress_name} in namespace {namespace} does not exist"
            else:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Error checking Ingress {ingress_name}: {str(e)[:50]}..."
                }

        # Create or update Ingress
        ingress_body = client.V1Ingress(
            metadata=client.V1ObjectMeta(
                name=ingress_name,
                namespace=namespace,
                annotations=annotations or {}
            ),
            spec=client.V1IngressSpec(**spec)
        )

        if not exists:
            try:
                networking_v1_api.create_namespaced_ingress(namespace=namespace, body=ingress_body)
                updated = True
                message = f"Ingress {ingress_name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to create Ingress {ingress_name}: {str(e)}..."
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if exists and hasattr(ingress, 'metadata') and hasattr(ingress.metadata, 'resource_version'):
                    ingress_body.metadata.resource_version = ingress.metadata.resource_version
                networking_v1_api.replace_namespaced_ingress(name=ingress_name, namespace=namespace, body=ingress_body)
                updated = True
                message = f"Ingress {ingress_name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to update Ingress {ingress_name}: {str(e)}..."
                }

        return {
            'success': True,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Ingress operation error: {str(e)[:100]}..."
        }
def certmanager_certificate_present(namespace, certificate_name, spec, annotations=None):
    """
    Ensure that a Cert-Manager Certificate resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    Args:
        namespace (str): The namespace for the Certificate resource.
        certificate_name (str): The name of the Certificate resource.
        spec (dict): The specification for the Certificate resource, including issuerRef, commonName, dnsNames, etc.
        annotations (dict, optional): Annotations to apply to the Certificate. Defaults to None.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.certmanager_certificate_present cert-manager my-certificate spec_dict annotations_dict
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        group = "cert-manager.io"
        version = "v1"
        plural = "certificates"

        exists = False
        updated = False
        matches = False

        # Check if Certificate exists
        try:
            certificate = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=namespace, plural=plural, name=certificate_name
            )
            exists = True
            current_spec = certificate.get('spec', {})
            current_annotations = certificate.get('metadata', {}).get('annotations', {})
            desired_annotations = annotations or {}
            desired_spec = spec

            # Check if spec and annotations match
            if current_spec == desired_spec and current_annotations == desired_annotations:
                matches = True
                message = f"Certificate {certificate_name} in namespace {namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"Certificate {certificate_name} in namespace {namespace} exists but spec or annotations differ"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"Certificate {certificate_name} in namespace {namespace} does not exist"
            else:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Error checking Certificate {certificate_name}: {str(e)[:50]}..."
                }

        # Create or update Certificate
        certificate_body = {
            "apiVersion": f"{group}/{version}",
            "kind": "Certificate",
            "metadata": {
                "name": certificate_name,
                "namespace": namespace,
                "annotations": annotations or {}
            },
            "spec": spec
        }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group, version=version, namespace=namespace, plural=plural, body=certificate_body
                )
                updated = True
                message = f"Certificate {certificate_name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to create Certificate {certificate_name}: {str(e)[:50]}..."
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if exists and 'metadata' in certificate and 'resourceVersion' in certificate['metadata']:
                    certificate_body['metadata']['resourceVersion'] = certificate['metadata']['resourceVersion']
                custom_api.replace_namespaced_custom_object(
                    group=group, version=version, namespace=namespace, plural=plural, name=certificate_name, body=certificate_body
                )
                updated = True
                message = f"Certificate {certificate_name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to update Certificate {certificate_name}: {str(e)[:50]}..."
                }

        return {
            'success': True,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Certificate operation error: {str(e)[:50]}..."
        }
def cnpg_cluster_present(namespace, cluster_name, spec):
    """
    Ensure that a CloudNativePG Cluster Custom Resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    Args:
        namespace (str): The namespace for the Cluster resource.
        cluster_name (str): The name of the Cluster resource.
        spec (dict): The specification for the Cluster resource, including instances, imageName, storage, etc.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.cnpg_cluster_present cnpg-system my-cluster spec_dict
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        group = "postgresql.cnpg.io"
        version = "v1"
        plural = "clusters"

        exists = False
        updated = False
        matches = False

        # Check if Cluster exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=namespace, plural=plural, name=cluster_name
            )
            exists = True
            current_spec = resource.get('spec', {})
            if current_spec == spec:
                matches = True
                message = f"Cluster {cluster_name} in namespace {namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"Cluster {cluster_name} in namespace {namespace} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"Cluster {cluster_name} in namespace {namespace} does not exist"
            else:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Error checking Cluster {cluster_name}: {str(e)[:50]}..."
                }

        # Create or update Cluster
        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "Cluster",
            "metadata": {
                "name": cluster_name,
                "namespace": namespace
            },
            "spec": spec
        }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group, version=version, namespace=namespace, plural=plural, body=body
                )
                updated = True
                message = f"Cluster {cluster_name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to create Cluster {cluster_name}: {str(e)}..."
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if 'metadata' in resource and 'resourceVersion' in resource['metadata']:
                    body['metadata']['resourceVersion'] = resource['metadata']['resourceVersion']
                custom_api.replace_namespaced_custom_object(
                    group=group, version=version, namespace=namespace, plural=plural, name=cluster_name, body=body
                )
                updated = True
                message = f"Cluster {cluster_name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to update Cluster {cluster_name}: {str(e)[:50]}..."
                }
        return {
            'success': True,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Cluster operation error: {str(e)[:50]}..."
        }
def secret_present(namespace, secret_name, data, secret_type='Opaque', labels=None, annotations=None):
    """
    Ensure that a Kubernetes Secret exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if the data, labels, or annotations differ.

    Args:
        namespace (str): The namespace for the Secret.
        secret_name (str): The name of the Secret.
        data (dict): The data to store in the Secret (key-value pairs). Values will be base64 encoded.
        secret_type (str, optional): The type of Secret (e.g., 'Opaque', 'kubernetes.io/tls'). Defaults to 'Opaque'.
        labels (dict, optional): Labels to apply to the Secret. Defaults to None.
        annotations (dict, optional): Annotations to apply to the Secret. Defaults to None.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.secret_present my-namespace my-secret "{'key1': 'value1', 'key2': 'value2'}"
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()
        exists = False
        updated = False
        matches = False

        # Check if Secret exists
        try:
            secret = core_v1_api.read_namespaced_secret(name=secret_name, namespace=namespace)
            exists = True
            current_data = secret.data or {}
            current_labels = secret.metadata.labels or {}
            current_annotations = secret.metadata.annotations or {}
            current_type = secret.type or 'Opaque'

            # Decode current data from base64 for comparison
            decoded_current_data = {}
            for k, v in current_data.items():
                try:
                    decoded_current_data[k] = base64.b64decode(v).decode('utf-8')
                except Exception:
                    decoded_current_data[k] = v  # If decoding fails, keep as is for comparison

            desired_labels = labels or {}
            desired_annotations = annotations or {}
            if (decoded_current_data == data and
                current_labels == desired_labels and
                current_annotations == desired_annotations and
                current_type == secret_type):
                matches = True
                message = f"Secret {secret_name} in namespace {namespace} already exists and matches desired state"
            else:
                matches = False
                message = f"Secret {secret_name} in namespace {namespace} exists but content differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"Secret {secret_name} in namespace {namespace} does not exist"
            else:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Error checking Secret {secret_name}: {str(e)[:50]}..."
                }

        # Encode data to base64 for Secret creation/update
        encoded_data = {}
        for k, v in data.items():
            if isinstance(v, str):
                encoded_data[k] = base64.b64encode(v.encode('utf-8')).decode('utf-8')
            else:
                encoded_data[k] = base64.b64encode(str(v).encode('utf-8')).decode('utf-8')

        # Create or update Secret
        secret_body = client.V1Secret(
            metadata=client.V1ObjectMeta(
                name=secret_name,
                namespace=namespace,
                labels=labels or {},
                annotations=annotations or {}
            ),
            data=encoded_data,
            type=secret_type
        )

        if not exists:
            try:
                core_v1_api.create_namespaced_secret(namespace=namespace, body=secret_body)
                updated = True
                message = f"Secret {secret_name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to create Secret {secret_name}: {str(e)[:50]}..."
                }
        elif not matches:
            try:
                core_v1_api.replace_namespaced_secret(name=secret_name, namespace=namespace, body=secret_body)
                updated = True
                message = f"Secret {secret_name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to update Secret {secret_name}: {str(e)[:50]}..."
                }

        return {
            'success': True,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Secret operation error: {str(e)[:50]}..."
        }
        
def keycloak_cluster_present(namespace, name, hostname, start_optimized=False, instances=2, image=None, db_vendor="postgres", db_host=None, db_port=5432, db_name="keycloak", db_user_name_secret_name=None, db_user_name_secret_key=None, db_password_secret_name=None, db_password_secret_key=None, ingress_enabled=False, proxy_headers="xforwarded", tls_secret=None):
    """
    Ensure that a Keycloak Custom Resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    namespace
        The namespace for the Keycloak resource.

    name
        The name of the Keycloak resource.
    hostname
        the fqdn of the service

    start_optimized
        Optional. Whether to start Keycloak with optimized settings. Defaults to False.

    instances
        Optional. Number of Keycloak instances. Defaults to 2.

    image
        Required. The Docker image for Keycloak.

    db_vendor
        Optional. Database vendor for Keycloak. Defaults to "postgres".

    db_host
        Required. Database host for Keycloak.

    db_port
        Optional. Database port for Keycloak. Defaults to 5432.

    db_name
        Optional. Database name for Keycloak. Defaults to "keycloak".

    db_user_name_secret_name
        Required. Name of the Secret containing the database username.

    db_user_name_secret_key
        Required. Key in the Secret for the database username.

    db_password_secret_name
        Required. Name of the Secret containing the database password.

    db_password_secret_key
        Required. Key in the Secret for the database password.

    ingress_enabled
        Optional. Whether to enable ingress for Keycloak. Defaults to False.

    proxy_headers
        Optional. Proxy headers setting for Keycloak. Defaults to "xforwarded".

    tls_secret
        Optional. Name of the TLS Secret for securing HTTP traffic. Defaults to None.
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        group = "k8s.keycloak.org"
        version = "v2alpha1"
        plural = "keycloaks"

        exists = False
        updated = False
        matches = False

        # Validate required fields
        if not image:
            return {
                'success': False,
                'updated': False,
                'message': "Error: 'image' is a required field for Keycloak configuration."
            }
        if not db_host:
            return {
                'success': False,
                'updated': False,
                'message': "Error: 'db_host' is a required field for Keycloak configuration."
            }
        if not db_user_name_secret_name or not db_user_name_secret_key:
            return {
                'success': False,
                'updated': False,
                'message': "Error: 'db_user_name_secret_name' and 'db_user_name_secret_key' are required fields for Keycloak configuration."
            }
        if not db_password_secret_name or not db_password_secret_key:
            return {
                'success': False,
                'updated': False,
                'message': "Error: 'db_password_secret_name' and 'db_password_secret_key' are required fields for Keycloak configuration."
            }

        # Build the spec for Keycloak with hostname nested under hostname key and tlsSecret under http
        spec = {
            "startOptimized": start_optimized,
            "instances": instances,
            "image": image,
            "hostname": {
                "hostname": 'https://' + hostname,  # Nested hostname as per Keycloak Operator documentation
                "admin": 'https://admin' + name + 'rsc.gacyberrange.org',
                "backchannelDynamic": True
            },
            "db": {
                "vendor": db_vendor,
                "host": db_host,
                "port": db_port,
                "database": db_name,  # Added database name field
                "usernameSecret": {
                    "name": db_user_name_secret_name,
                    "key": db_user_name_secret_key
                },
                "passwordSecret": {
                    "name": db_password_secret_name,
                    "key": db_password_secret_key
                }
            },
            "ingress": {
                "enabled": ingress_enabled
            },
            "proxy": {
                "headers": proxy_headers
            },
            "http": {}
        }

        # Add tlsSecret to http if provided
        if tls_secret:
            spec["http"]["tlsSecret"] = tls_secret

        # Check if Keycloak exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=namespace, plural=plural, name=name
            )
            exists = True
            current_spec = resource.get('spec', {})
            if current_spec == spec:
                matches = True
                message = f"Keycloak {name} in namespace {namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"Keycloak {name} in namespace {namespace} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"Keycloak {name} in namespace {namespace} does not exist"
            else:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Error checking Keycloak {name}: {str(e)[:50]}..."
                }

        # Create or update Keycloak
        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "Keycloak",
            "metadata": {
                "name": name,
                "namespace": namespace
            },
            "spec": spec
        }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group, version=version, namespace=namespace, plural=plural, body=body
                )
                updated = True
                message = f"Keycloak {name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to create Keycloak {name}: {str(e)[:50]}..."
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if 'metadata' in resource and 'resourceVersion' in resource['metadata']:
                    body['metadata']['resourceVersion'] = resource['metadata']['resourceVersion']
                custom_api.replace_namespaced_custom_object(
                    group=group, version=version, namespace=namespace, plural=plural, name=name, body=body
                )
                updated = True
                message = f"Keycloak {name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'message': f"Failed to update Keycloak {name}: {str(e)}..."
                }
        return {
            'success': True,
            'updated': updated,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Keycloak operation error: {str(e)[:50]}..."
        }

def certificate_present(namespace, certificate_name, common_name, email_address, dns_name=None, duration="2160h", renew_before="360h", issuer_ref="self-signed"):
    """
    Ensure that a Cert-Manager Certificate resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.
    Also checks if the associated Secret resource exists.

    Args:
        namespace (str): The namespace for the Certificate resource.
        certificate_name (str): The name of the Certificate resource.
        common_name (str): The Common Name (CN) for the certificate.
        email_address (str): Ignored. Previously used for the certificate subject, now omitted for ACME compatibility.
        dns_name (str, optional): DNS name for the certificate. Defaults to None.
        duration (str, optional): Duration of the certificate validity. Defaults to "2160h" (90 days).
        renew_before (str, optional): Time before expiration to renew the certificate. Defaults to "360h" (15 days).
        issuer_ref (str or dict/list, optional): Reference to the issuer. Can be a string (name only), or a dict/list with 'name' and 'kind'. Defaults to "self-signed".

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'secret_exists' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-k8s.certificate_present my-namespace my-cert example.com admin@example.com dns_name=www.example.com issuer_ref="{'name': 'letsencrypt-prod', 'kind': 'ClusterIssuer'}"
    """
    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        core_v1_api = client.CoreV1Api()
        group = "cert-manager.io"
        version = "v1"
        plural = "certificates"

        exists = False
        updated = False
        matches = False
        secret_exists = False

        # Parse issuer_ref to extract name and kind
        issuer_name = "self-signed"
        issuer_kind = "Issuer"
        if isinstance(issuer_ref, (dict, list)):
            if isinstance(issuer_ref, dict):
                issuer_name = issuer_ref.get('name', 'self-signed')
                issuer_kind = issuer_ref.get('kind', 'Issuer')
            else:  # list format as in pillar example
                for item in issuer_ref:
                    if 'name' in item:
                        issuer_name = item['name']
                    if 'kind' in item:
                        issuer_kind = item['kind']
        else:
            issuer_name = issuer_ref

        # Ensure dnsNames includes common_name if applicable for ACME
        dns_names = [common_name]
        if dns_name and dns_name not in dns_names:
            dns_names.append(dns_name)

        # Build the spec for Certificate (email_address is ignored for ACME compatibility)
        spec = {
            "secretName": certificate_name,
            "commonName": common_name,
            "dnsNames": dns_names,
            "duration": duration,
            "renewBefore": renew_before,
            "issuerRef": {
                "name": issuer_name,
                "kind": issuer_kind
            }
        }

        # Check if Certificate exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group, version=version, namespace=namespace, plural=plural, name=certificate_name
            )
            exists = True
            current_spec = resource.get('spec', {})
            if current_spec == spec:
                matches = True
                message = f"Certificate {certificate_name} in namespace {namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"Certificate {certificate_name} in namespace {namespace} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"Certificate {certificate_name} in namespace {namespace} does not exist"
            else:
                return {
                    'success': False,
                    'updated': False,
                    'secret_exists': False,
                    'message': f"Error checking Certificate {certificate_name}: {str(e)[:50]}..."
                }

        # Check if associated Secret exists
        try:
            core_v1_api.read_namespaced_secret(name=certificate_name, namespace=namespace)
            secret_exists = True
        except ApiException as e:
            if e.status == 404:
                secret_exists = False
            else:
                return {
                    'success': False,
                    'updated': False,
                    'secret_exists': False,
                    'message': f"Error checking Secret {certificate_name}: {str(e)[:50]}..."
                }

        # Create or update Certificate
        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "Certificate",
            "metadata": {
                "name": certificate_name,
                "namespace": namespace
            },
            "spec": spec
        }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group, version=version, namespace=namespace, plural=plural, body=body
                )
                updated = True
                message = f"Certificate {certificate_name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'secret_exists': secret_exists,
                    'message': f"Failed to create Certificate {certificate_name}: {str(e)[:50]}..."
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if 'metadata' in resource and 'resourceVersion' in resource['metadata']:
                    body['metadata']['resourceVersion'] = resource['metadata']['resourceVersion']
                custom_api.replace_namespaced_custom_object(
                    group=group, version=version, namespace=namespace, plural=plural, name=certificate_name, body=body
                )
                updated = True
                message = f"Certificate {certificate_name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    'success': False,
                    'updated': False,
                    'secret_exists': secret_exists,
                    'message': f"Failed to update Certificate {certificate_name}: {str(e)[:50]}..."
                }
        return {
            'success': True,
            'updated': updated,
            'secret_exists': secret_exists,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'secret_exists': False,
            'message': f"Certificate operation error: {str(e)[:50]}..."
        }