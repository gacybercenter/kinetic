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
        # Load kubeconfig file (ensure access to cluster config)
        # Use in-cluster config if running inside a pod, otherwise kubeconfig
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        # Create an instance of the Custom Objects API
        custom_api = client.CustomObjectsApi()

        # Define the Custom Resource details
        group = "metal3.io"
        version = "v1alpha1"
        plural = "hardwaredata"

        # Get the HardwareData resource
        resource = custom_api.get_namespaced_custom_object(
            group=group,
            version=version,
            namespace=namespace,
            plural=plural,
            name=resource_name
        )

        # Extract the NICs from the hardware spec
        nics = resource.get('spec', {}).get('hardware', {}).get('nics', [])

        # Search for the interface by name
        for nic in nics:
            if nic.get('name') == interface_name:
                return {
                    'success': True,
                    'mac': nic.get('mac'),
                    'message': f"Found MAC address for interface {interface_name}"
                }

        return {
            'success': False,
            'mac': '',
            'message': f"No interface found with name: {interface_name}"
        }

    except ApiException as e:
        return {
            'success': False,
            'mac': '',
            'message': f"Exception when calling Kubernetes API: {str(e)}"
        }
    except Exception as e:
        return {
            'success': False,
            'mac': '',
            'message': f"An error occurred: {str(e)}"
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
        # Load kubeconfig file (ensure access to cluster config)
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        # Create an instance of the Custom Objects API
        custom_api = client.CustomObjectsApi()

        # Define the Custom Resource details
        group = "metal3.io"
        version = "v1alpha1"
        plural = "hardwaredata"

        # Get the HardwareData resource
        resource = custom_api.get_namespaced_custom_object(
            group=group,
            version=version,
            namespace=namespace,
            plural=plural,
            name=resource_name
        )

        # Extract the NICs from the hardware spec
        nics = resource.get('spec', {}).get('hardware', {}).get('nics', [])
        interfaces = {nic.get('name'): nic.get('mac') for nic in nics if nic.get('name') and nic.get('mac')}

        return {
            'success': True,
            'interfaces': interfaces,
            'message': f"Retrieved {len(interfaces)} interfaces for {resource_name}"
        }

    except ApiException as e:
        return {
            'success': False,
            'interfaces': {},
            'message': f"Exception when calling Kubernetes API: {str(e)}"
        }
    except Exception as e:
        return {
            'success': False,
            'interfaces': {},
            'message': f"An error occurred: {str(e)}"
        }

def bmh_replace(namespace, bmh_name, pillar_data, bmh_template_path='salt://formulas/bmo/files/bmh.j2', network_template_path='salt://formulas/bmo/files/network-data.j2', userdata_template_path='salt://formulas/bmo/files/cloudinit.j2'):
    """
    Ensure that the Bare Metal Host (BMH) object, network data, and userdata in Kubernetes match the desired state
    defined by pillar data and Jinja2 templates. Deletes and recreates BMH if it needs updating or if network/userdata
    are updated or created. Creates or replaces other objects as needed.

    Args:
        namespace (str): The namespace of the Bare Metal Host resource in Kubernetes.
        bmh_name (str): The name of the Bare Metal Host resource.
        pillar_data (dict): Pillar data containing the desired BMH, network, and userdata configuration.
        bmh_template_path (str, optional): Salt URI to the Jinja2 template file for BMH.
        network_template_path (str, optional): Salt URI to the Jinja2 template file for network data.
        userdata_template_path (str, optional): Salt URI to the Jinja2 template file for userdata.

    Returns:
        dict: A dictionary with 'success' (bool), 'bmh_updated' (bool), 'network_updated' (bool), 'userdata_updated' (bool),
              'bmh_result' (dict), 'network_result' (dict), 'userdata_result' (dict), and 'message' (str for status or error).

    CLI Example:
        salt '*' kinetic-k8s.bmh_replace baremetal-operator-system compute-133-26 pillar_data
    """
    try:
        bmh_updated = False
        network_updated = False
        userdata_updated = False
        bmh_result = {}
        network_result = {}
        userdata_result = {}

        bmh_exists = False
        bmh_matches = False
        current_bmh = {}
        desired_bmh = {}
        bmh_differences = {}

        network_exists = False
        network_matches = False
        current_network = {}
        desired_network = {}
        network_differences = {}

        userdata_exists = False
        userdata_matches = False
        current_userdata = {}
        desired_userdata = {}
        userdata_differences = {}

        # Load Kubernetes configuration for updates
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        core_v1_api = client.CoreV1Api()

        # Step 1: Retrieve the existing BMH from Kubernetes
        try:
            group = "metal3.io"
            version = "v1alpha1"
            plural = "baremetalhosts"
            resource = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=bmh_name
            )
            bmh_exists = True
            current_bmh = {
                'name': resource.get('metadata', {}).get('name', ''),
                'namespace': resource.get('metadata', {}).get('namespace', ''),
                'status': resource.get('status', {}),
                'spec': resource.get('spec', {})
            }
        except ApiException as e:
            bmh_exists = False
            current_bmh = {}
            bmh_message = f"BMH {bmh_name} not found: {str(e)}"
        except Exception as e:
            bmh_exists = False
            current_bmh = {}
            bmh_message = f"Error fetching BMH: {str(e)}"

        # Step 2: Render the desired BMH configuration from pillar data using Jinja2 template in memory
        try:
            # Prepare the context for rendering the BMH template
            network_data_name = f"{bmh_name}-network-data"
            userdata_name = f"{bmh_name}-user-data"
            bmh_context = {
                'name': bmh_name,
                'namespace': namespace,
                'online': pillar_data.get('online', False),
                'address': pillar_data.get('bmc', {}).get('address', ''),
                'bootMACAddress': pillar_data.get('bootMACAddress', ''),
                'checksum': pillar_data.get('image', {}).get('checksum', ''),
                'format': pillar_data.get('image', {}).get('format', ''),
                'url': pillar_data.get('image', {}).get('url', ''),
                'rootdevice': pillar_data.get('rootDeviceHints', {}).get('deviceName', ''),
                'networkdata': network_data_name if 'network' in pillar_data else '',
                'userdata': userdata_name if 'network' in pillar_data else ''
            }

            # Use Salt's in-memory rendering for BMH template
            bmh_content = __salt__['cp.get_file_str'](bmh_template_path)
            if not bmh_content:
                raise Exception(f"Failed to read BMH template from {bmh_template_path}: Content is empty or inaccessible")

            rendered_bmh = __salt__['slsutil.renderer'](
                string=bmh_content,
                default_renderer='jinja|yaml',
                context=bmh_context
            )

            if not rendered_bmh:
                raise Exception("Failed to render BMH template: Empty or invalid output")

            # Parse the rendered YAML content into a dictionary
            import yaml
            desired_bmh = yaml.safe_load(rendered_bmh)

            # Compare the existing BMH spec with the desired spec
            if bmh_exists:
                current_bmh_spec = current_bmh.get('spec', {})
                desired_bmh_spec = desired_bmh.get('spec', {})
                for key in desired_bmh_spec:
                    if key not in current_bmh_spec or current_bmh_spec[key] != desired_bmh_spec[key]:
                        bmh_differences[key] = {
                            'current': current_bmh_spec.get(key, 'not set'),
                            'desired': desired_bmh_spec[key]
                        }
                bmh_matches = len(bmh_differences) == 0
            else:
                bmh_matches = False
        except Exception as bmh_render_error:
            return {
                'success': False,
                'bmh_updated': False,
                'network_updated': False,
                'userdata_updated': False,
                'bmh_result': {'error': str(bmh_render_error)},
                'network_result': {},
                'userdata_result': {},
                'message': f"Failed to render BMH template: {str(bmh_render_error)}"
            }

        # Step 3: Retrieve the existing network data ConfigMap from Kubernetes
        if 'network' in pillar_data:
            try:
                network_data_name = f"{bmh_name}-network-data"
                network_cm = core_v1_api.read_namespaced_config_map(name=network_data_name, namespace=namespace)
                network_exists = True
                current_network = network_cm.data if network_cm.data else {}
            except ApiException as ne:
                network_exists = False
                current_network = {}
                network_message = f"Network data ConfigMap {network_data_name} not found: {str(ne)}"
            except Exception as ne:
                network_exists = False
                current_network = {}
                network_message = f"Error fetching network data: {str(ne)}"
        else:
            network_exists = False
            current_network = {}

        # Step 4: Render the desired network data configuration from pillar data using Jinja2 template in memory
        if 'network' in pillar_data:
            try:
                # Prepare the context for rendering the network data template
                full_pillar = __salt__['pillar.get']('hosts:compute', {})
                interface = full_pillar.get('interface') if full_pillar else ''

                network_context = {
                    'pillar': {
                        'hosts': {
                            'compute': {
                                'interface': interface
                            }
                        }
                    },
                    'mac': pillar_data.get('bootMACAddress', ''),
                    'ip': pillar_data.get('network', {}).get('management_ip', ''),
                    'prefix': full_pillar.get('networks', {}).get('management', {}).get('netmask') if full_pillar else '',
                    'gateway': full_pillar.get('networks', {}).get('management', {}).get('gateway') if full_pillar else '',
                    'nameserver': full_pillar.get('ntp_server') if full_pillar else ''
                }

                # Use Salt's in-memory rendering for network data template
                network_content = __salt__['cp.get_file_str'](network_template_path)
                if not network_content:
                    raise Exception(f"Failed to read network template from {network_template_path}: Content is empty or inaccessible")

                rendered_network = __salt__['slsutil.renderer'](
                    string=network_content,
                    default_renderer='jinja',
                    context=network_context
                )

                if not rendered_network:
                    raise Exception("Failed to render network template: Empty or invalid output")

                # Parse the rendered JSON content into a dictionary
                import json
                desired_network = json.loads(rendered_network)

                # Compare the existing network data with the desired network data
                if network_exists:
                    current_network_data = current_network
                    if isinstance(current_network, dict) and len(current_network) == 1 and 'networkData' in current_network:
                        try:
                            current_network_data = json.loads(current_network['networkData'])
                        except Exception:
                            current_network_data = current_network

                    for key in desired_network:
                        if key not in current_network_data or current_network_data[key] != desired_network[key]:
                            network_differences[key] = {
                                'current': current_network_data.get(key, 'not set'),
                                'desired': desired_network[key]
                            }
                    network_matches = len(network_differences) == 0
                else:
                    network_matches = False
            except Exception as network_render_error:
                return {
                    'success': False,
                    'bmh_updated': False,
                    'network_updated': False,
                    'userdata_updated': False,
                    'bmh_result': {},
                    'network_result': {'error': str(network_render_error)},
                    'userdata_result': {},
                    'message': f"Failed to render network data template: {str(network_render_error)}"
                }
        else:
            desired_network = {}
            network_matches = False
            network_message = f"Network data not applicable for {bmh_name}"

        # Step 5: Retrieve the existing userdata ConfigMap from Kubernetes
        if 'network' in pillar_data:
            try:
                userdata_name = f"{bmh_name}-user-data"
                userdata_cm = core_v1_api.read_namespaced_config_map(name=userdata_name, namespace=namespace)
                userdata_exists = True
                current_userdata = userdata_cm.data if userdata_cm.data else {}
            except ApiException as ue:
                userdata_exists = False
                current_userdata = {}
                userdata_message = f"Userdata ConfigMap {userdata_name} not found: {str(ue)}"
            except Exception as ue:
                userdata_exists = False
                current_userdata = {}
                userdata_message = f"Error fetching userdata: {str(ue)}"
        else:
            userdata_exists = False
            current_userdata = {}

        # Step 6: Render the desired userdata configuration from pillar data using Jinja2 template in memory
        if 'network' in pillar_data:
            try:
                # Prepare the context for rendering the userdata template (cloudinit.j2)
                full_pillar = __salt__['pillar.get']('', {})  # Get the full pillar to access node_deploy_key
                userdata_context = {
                    'pillar': {
                        'node_deploy_key': full_pillar.get('node_deploy_key', '')
                    },
                    'pass': pillar_data.get('root_password_crypted', '')
                }

                # Use Salt's in-memory rendering for userdata template
                userdata_content = __salt__['cp.get_file_str'](userdata_template_path)
                if not userdata_content:
                    raise Exception(f"Failed to read userdata template from {userdata_template_path}: Content is empty or inaccessible")

                rendered_userdata = __salt__['slsutil.renderer'](
                    string=userdata_content,
                    default_renderer='jinja',
                    context=userdata_context
                )

                if not rendered_userdata:
                    raise Exception("Failed to render userdata template: Empty or invalid output")

                # Since cloudinit.j2 is plain text, store as a string in a dict
                desired_userdata = {'cloud-config': rendered_userdata}

                # Compare the existing userdata with the desired userdata
                if userdata_exists:
                    current_userdata_data = current_userdata
                    if isinstance(current_userdata, dict) and 'cloud-config' in current_userdata:
                        current_userdata_data = current_userdata.get('cloud-config', '')
                    elif isinstance(current_userdata, dict) and len(current_userdata) == 1:
                        current_userdata_data = list(current_userdata.values())[0]

                    desired_userdata_data = desired_userdata.get('cloud-config', '')
                    if current_userdata_data != desired_userdata_data:
                        userdata_differences['cloud-config'] = {
                            'current': current_userdata_data if current_userdata_data else 'not set',
                            'desired': desired_userdata_data
                        }
                    userdata_matches = len(userdata_differences) == 0
                else:
                    userdata_matches = False
            except Exception as userdata_render_error:
                return {
                    'success': False,
                    'bmh_updated': False,
                    'network_updated': False,
                    'userdata_updated': False,
                    'bmh_result': {},
                    'network_result': {},
                    'userdata_result': {'error': str(userdata_render_error)},
                    'message': f"Failed to render userdata template: {str(userdata_render_error)}"
                }
        else:
            desired_userdata = {}
            userdata_matches = False
            userdata_message = f"Userdata not applicable for {bmh_name}"

        # Step 7: Update or create network data ConfigMap if it doesn't exist or doesn't match
        if 'network' in pillar_data and (not network_exists or not network_matches):
            try:
                network_data_name = f"{bmh_name}-network-data"
                network_data_str = json.dumps(desired_network)
                body = client.V1ConfigMap(
                    metadata=client.V1ObjectMeta(name=network_data_name, namespace=namespace),
                    data={'networkData': network_data_str}
                )

                if network_exists:
                    network_result = core_v1_api.replace_namespaced_config_map(
                        name=network_data_name,
                        namespace=namespace,
                        body=body
                    )
                    network_updated = True
                    network_message = f"Network data ConfigMap {network_data_name} updated"
                else:
                    network_result = core_v1_api.create_namespaced_config_map(
                        namespace=namespace,
                        body=body
                    )
                    network_updated = True
                    network_message = f"Network data ConfigMap {network_data_name} created"
            except ApiException as e:
                network_updated = False
                network_message = f"Failed to update/create network data ConfigMap {network_data_name}: {str(e)}"
                network_result = {'error': str(e)}
        else:
            network_message = f"Network data for {bmh_name} already matches desired state or not applicable"
            network_result = current_network

        # Step 8: Update or create userdata ConfigMap if it doesn't exist or doesn't match
        if 'network' in pillar_data and (not userdata_exists or not userdata_matches):
            try:
                userdata_name = f"{bmh_name}-user-data"
                userdata_str = desired_userdata.get('cloud-config', '')
                body = client.V1ConfigMap(
                    metadata=client.V1ObjectMeta(name=userdata_name, namespace=namespace),
                    data={'cloud-config': userdata_str}
                )

                if userdata_exists:
                    userdata_result = core_v1_api.replace_namespaced_config_map(
                        name=userdata_name,
                        namespace=namespace,
                        body=body
                    )
                    userdata_updated = True
                    userdata_message = f"Userdata ConfigMap {userdata_name} updated"
                else:
                    userdata_result = core_v1_api.create_namespaced_config_map(
                        namespace=namespace,
                        body=body
                    )
                    userdata_updated = True
                    userdata_message = f"Userdata ConfigMap {userdata_name} created"
            except ApiException as e:
                userdata_updated = False
                userdata_message = f"Failed to update/create userdata ConfigMap {userdata_name}: {str(e)}"
                userdata_result = {'error': str(e)}
        else:
            userdata_message = f"Userdata for {bmh_name} already matches desired state or not applicable"
            userdata_result = current_userdata

        # Step 9: Delete and recreate BMH if it doesn't exist, doesn't match, or if network/userdata were updated
        if not bmh_exists or not bmh_matches or network_updated or userdata_updated:
            try:
                group = "metal3.io"
                version = "v1alpha1"
                plural = "baremetalhosts"
                body = desired_bmh

                if bmh_exists:
                    custom_api.delete_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        name=bmh_name,
                        body=client.V1DeleteOptions(propagation_policy='Foreground', grace_period_seconds=5)
                    )
                    bmh_message = f"BMH {bmh_name} deleted (to be recreated due to mismatch or network/userdata update)"
                else:
                    bmh_message = f"BMH {bmh_name} does not exist, will be created"

                bmh_result = custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=body
                )
                bmh_updated = True
                bmh_message += f"; BMH {bmh_name} created"
            except ApiException as e:
                bmh_updated = False
                bmh_message = f"Failed to delete/recreate BMH {bmh_name}: {str(e)}"
                bmh_result = {'error': str(e)}
        else:
            bmh_message = f"BMH {bmh_name} already matches desired state"
            bmh_result = current_bmh

        return {
            'success': True,
            'bmh_updated': bmh_updated,
            'network_updated': network_updated,
            'userdata_updated': userdata_updated,
            'bmh_result': bmh_result,
            'network_result': network_result,
            'userdata_result': userdata_result,
            'message': f"BMH: {bmh_message}; Network: {network_message}; Userdata: {userdata_message}"
        }

    except Exception as e:
        return {
            'success': False,
            'bmh_updated': False,
            'network_updated': False,
            'userdata_updated': False,
            'bmh_result': {},
            'network_result': {},
            'userdata_result': {},
            'message': f"An error occurred during bmh_replace operation: {str(e)}"
        }