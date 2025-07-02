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

def bmh_present(namespace, bmh_name, pillar_data, bmh_template_path='salt://formulas/bmo/files/bmh.j2'):
    """
    Ensure that the Bare Metal Host (BMH) object in Kubernetes matches the desired state
    defined by pillar data and Jinja2 template. Updates BMH if possible, or deletes and recreates
    if it needs updating and is in an error state, waiting for deletion to complete.

    Args:
        namespace (str): The namespace of the Bare Metal Host resource in Kubernetes.
        bmh_name (str): The name of the Bare Metal Host resource.
        pillar_data (dict): Pillar data containing the desired BMH configuration.
        bmh_template_path (str, optional): Salt URI to the Jinja2 template file for BMH.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'result' (dict), and 'message' (str for status or error).

    CLI Example:
        salt '*' kinetic-k8s.bmh_present baremetal-operator-system compute-133-26 pillar_data
    """
    try:
        updated = False
        result = {}
        exists = False
        matches = False
        in_error_state = False
        current_bmh = {}
        desired_bmh = {}
        differences = {}

        # Load Kubernetes configuration for updates
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()

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
            exists = True
            current_bmh = {
                'name': resource.get('metadata', {}).get('name', ''),
                'namespace': resource.get('metadata', {}).get('namespace', ''),
                'status': resource.get('status', {}),
                'spec': resource.get('spec', {})
            }
            # Check if BMH is in an error state
            status = current_bmh.get('status', {})
            error_message = status.get('errorMessage', '')
            provisioning_state = status.get('provisioning', {}).get('state', '')
            in_error_state = error_message != '' or provisioning_state == 'error'
        except ApiException as e:
            exists = False
            current_bmh = {}
            message = f"BMH {bmh_name} not found: {str(e)}"
        except Exception as e:
            exists = False
            current_bmh = {}
            message = f"Error fetching BMH: {str(e)}"

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
            try:
                bmh_content = __salt__['cp.get_file_str'](bmh_template_path)
                if not bmh_content:
                    raise Exception(f"Failed to read BMH template from {bmh_template_path}: Content is empty or inaccessible. Verify the path exists in Salt file roots.")
                # Strip shebang line if present to avoid rendering issues
                if bmh_content.startswith('#!'):
                    bmh_content_lines = bmh_content.splitlines()
                    bmh_content = '\n'.join(bmh_content_lines[1:]) if len(bmh_content_lines) > 1 else ''
                    if not bmh_content:
                        raise Exception(f"BMH template at {bmh_template_path} is empty after removing shebang line.")
            except Exception as file_error:
                return {
                    'success': False,
                    'updated': False,
                    'result': {'error': str(file_error)},
                    'message': f"Failed to retrieve BMH template file from {bmh_template_path}: {str(file_error)}. Check if the file exists in Salt file roots."
                }

            rendered_bmh = __salt__['slsutil.renderer'](
                string=bmh_content,
                default_renderer='jinja|yaml',
                context=bmh_context
            )

            if not rendered_bmh:
                raise Exception("Failed to render BMH template: Empty or invalid output")

            # Handle the case where rendered_bmh is already a dictionary (parsed YAML)
            import yaml
            if isinstance(rendered_bmh, dict):
                desired_bmh = rendered_bmh
            else:
                # If it's a string, parse it as YAML
                desired_bmh = yaml.safe_load(rendered_bmh)

            # Compare the existing BMH spec with the desired spec
            if exists:
                current_bmh_spec = current_bmh.get('spec', {})
                desired_bmh_spec = desired_bmh.get('spec', {})
                for key in desired_bmh_spec:
                    if key not in current_bmh_spec or current_bmh_spec[key] != desired_bmh_spec[key]:
                        differences[key] = {
                            'current': current_bmh_spec.get(key, 'not set'),
                            'desired': desired_bmh_spec[key]
                        }
                matches = len(differences) == 0
            else:
                matches = False
        except Exception as bmh_render_error:
            return {
                'success': False,
                'updated': False,
                'result': {'error': str(bmh_render_error)},
                'message': f"Failed to render BMH template: {str(bmh_render_error)}"
            }

        # Step 3: Update or create BMH based on existence, match status, and error state
        if not exists:
            try:
                group = "metal3.io"
                version = "v1alpha1"
                plural = "baremetalhosts"
                body = desired_bmh

                result = custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=body
                )
                updated = True
                message = f"BMH {bmh_name} created (did not exist)"
            except ApiException as e:
                updated = False
                message = f"Failed to create BMH {bmh_name}: {str(e)}"
                result = {'error': str(e)}
        elif not matches or in_error_state:
            try:
                group = "metal3.io"
                version = "v1alpha1"
                plural = "baremetalhosts"
                body = desired_bmh
                # Preserve metadata like resourceVersion for update
                if 'metadata' in current_bmh and 'resourceVersion' in current_bmh['metadata']:
                    if 'metadata' not in body:
                        body['metadata'] = {}
                    body['metadata']['resourceVersion'] = current_bmh['metadata'].get('resourceVersion', '')

                try:
                    # First attempt to update the existing BMH
                    result = custom_api.replace_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        name=bmh_name,
                        body=body
                    )
                    updated = True
                    message = f"BMH {bmh_name} updated (direct replacement)"
                except ApiException as update_error:
                    # If update fails and it's due to an error state requiring deletion, fall back to delete and recreate
                    if in_error_state:
                        import time
                        # Delete the BMH
                        custom_api.delete_namespaced_custom_object(
                            group=group,
                            version=version,
                            namespace=namespace,
                            plural=plural,
                            name=bmh_name,
                            body=client.V1DeleteOptions(propagation_policy='Foreground', grace_period_seconds=5)
                        )
                        message = f"BMH {bmh_name} deleted (due to error state or update failure: {str(update_error)})"

                        # Wait for deletion to complete
                        max_wait = 60  # Wait up to 60 seconds
                        wait_interval = 5  # Check every 5 seconds
                        wait_time = 0
                        while wait_time < max_wait:
                            try:
                                custom_api.get_namespaced_custom_object(
                                    group=group,
                                    version=version,
                                    namespace=namespace,
                                    plural=plural,
                                    name=bmh_name
                                )
                                time.sleep(wait_interval)
                                wait_time += wait_interval
                            except ApiException as get_error:
                                if get_error.status == 404:  # Not found, deletion complete
                                    message += f"; Deletion of BMH {bmh_name} completed after {wait_time} seconds"
                                    break
                                else:
                                    message += f"; Error checking deletion status for BMH {bmh_name}: {str(get_error)}"
                                    break
                        if wait_time >= max_wait:
                            message += f"; Timeout waiting for deletion of BMH {bmh_name} after {max_wait} seconds"

                        # Recreate after deletion
                        result = custom_api.create_namespaced_custom_object(
                            group=group,
                            version=version,
                            namespace=namespace,
                            plural=plural,
                            body=body
                        )
                        updated = True
                        message += f"; BMH {bmh_name} recreated after deletion"
                    else:
                        updated = False
                        message = f"Failed to update BMH {bmh_name}: {str(update_error)}"
                        result = {'error': str(update_error)}
            except ApiException as e:
                updated = False
                message = f"Failed to process BMH {bmh_name}: {str(e)}"
                result = {'error': str(e)}
        else:
            message = f"BMH {bmh_name} already matches desired state and is not in error state"
            result = current_bmh

        return {
            'success': True,
            'updated': updated,
            'result': result,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'result': {},
            'message': f"An error occurred during bmh_present operation: {str(e)}"
        }

def networkdata_present(namespace, bmh_name, pillar_data, network_template_path='salt://formulas/bmo/files/network-data.j2'):
    """
    Ensure that the network data ConfigMap in Kubernetes matches the desired state
    defined by pillar data and Jinja2 template. Creates or replaces the ConfigMap if it needs updating.

    Args:
        namespace (str): The namespace of the network data ConfigMap in Kubernetes.
        bmh_name (str): The name of the Bare Metal Host resource (used for ConfigMap naming).
        pillar_data (dict): Pillar data containing the desired network configuration.
        network_template_path (str, optional): Salt URI to the Jinja2 template file for network data.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'result' (dict), and 'message' (str for status or error).

    CLI Example:
        salt '*' kinetic-k8s.networkdata_present baremetal-operator-system compute-133-26 pillar_data
    """
    try:
        updated = False
        result = {}
        exists = False
        matches = False
        current_network = {}
        desired_network = {}
        differences = {}

        # Load Kubernetes configuration for updates
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()

        # Step 1: Retrieve the existing network data ConfigMap from Kubernetes
        if 'network' in pillar_data:
            try:
                network_data_name = f"{bmh_name}-network-data"
                network_cm = core_v1_api.read_namespaced_config_map(name=network_data_name, namespace=namespace)
                exists = True
                current_network = network_cm.data if network_cm.data else {}
            except ApiException as ne:
                exists = False
                current_network = {}
                message = f"Network data ConfigMap {network_data_name} not found: {str(ne)}"
            except Exception as ne:
                exists = False
                current_network = {}
                message = f"Error fetching network data: {str(ne)}"
        else:
            exists = False
            current_network = {}
            message = f"Network data not applicable for {bmh_name}"

        # Step 2: Render the desired network data configuration from pillar data using Jinja2 template in memory
        if 'network' in pillar_data:
            try:
                # Infer the BMH type from bmh_name (e.g., compute, controller, storage)
                bmh_type = bmh_name.split('-')[0].lower() if '-' in bmh_name else 'compute'
                
                # Fetch the appropriate hosts data based on the BMH type
                full_pillar = __salt__['pillar.get'](f'hosts:{bmh_type}', {})
                interface = full_pillar.get('interface') if full_pillar else ''

                network_context = {
                    'interface': interface,
                    'mac': pillar_data.get('bootMACAddress', ''),
                    'ip': pillar_data.get('network', {}).get('management_ip', ''),
                    'prefix': full_pillar.get('networking', {}).get('subnets', {}).get('management') if full_pillar else '',
                    'gateway': full_pillar.get('dhcp-options', {}).get('mgmt_gateway') if full_pillar else '',
                    'nameserver': full_pillar.get('dhcp-options', {}).get('dns') if full_pillar else ''
                }

                # Use Salt's in-memory rendering for network data template
                try:
                    network_content = __salt__['cp.get_file_str'](network_template_path)
                    if not network_content:
                        raise Exception(f"Failed to read network template from {network_template_path}: Content is empty or inaccessible. Verify the path exists in Salt file roots.")
                    # Strip shebang line if present to avoid rendering issues
                    if network_content.startswith('#!'):
                        network_content_lines = network_content.splitlines()
                        network_content = '\n'.join(network_content_lines[1:]) if len(network_content_lines) > 1 else ''
                        if not network_content:
                            raise Exception(f"Network template at {network_template_path} is empty after removing shebang line.")
                except Exception as file_error:
                    return {
                        'success': False,
                        'updated': False,
                        'result': {'error': str(file_error)},
                        'message': f"Failed to retrieve network template file from {network_template_path}: {str(file_error)}. Check if the file exists in Salt file roots."
                    }

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
                if exists:
                    current_network_data = current_network
                    if isinstance(current_network, dict) and len(current_network) == 1 and 'networkData' in current_network:
                        try:
                            current_network_data = json.loads(current_network['networkData'])
                        except Exception:
                            current_network_data = current_network

                    for key in desired_network:
                        if key not in current_network_data or current_network_data[key] != desired_network[key]:
                            differences[key] = {
                                'current': current_network_data.get(key, 'not set'),
                                'desired': desired_network[key]
                            }
                    matches = len(differences) == 0
                else:
                    matches = False
            except Exception as network_render_error:
                return {
                    'success': False,
                    'updated': False,
                    'result': {'error': str(network_render_error)},
                    'message': f"Failed to render network data template: {str(network_render_error)}"
                }
        else:
            desired_network = {}
            matches = False
            message = f"Network data not applicable for {bmh_name}"

        # Step 3: Update or create network data ConfigMap if it doesn't exist or doesn't match
        if 'network' in pillar_data and (not exists or not matches):
            try:
                network_data_name = f"{bmh_name}-network-data"
                network_data_str = json.dumps(desired_network)
                body = client.V1ConfigMap(
                    metadata=client.V1ObjectMeta(name=network_data_name, namespace=namespace),
                    data={'networkData': network_data_str}
                )

                if exists:
                    result = core_v1_api.replace_namespaced_config_map(
                        name=network_data_name,
                        namespace=namespace,
                        body=body
                    )
                    updated = True
                    message = f"Network data ConfigMap {network_data_name} updated"
                else:
                    result = core_v1_api.create_namespaced_config_map(
                        namespace=namespace,
                        body=body
                    )
                    updated = True
                    message = f"Network data ConfigMap {network_data_name} created"
            except ApiException as e:
                updated = False
                message = f"Failed to update/create network data ConfigMap {network_data_name}: {str(e)}"
                result = {'error': str(e)}
        else:
            message = f"Network data for {bmh_name} already matches desired state or not applicable"
            result = current_network

        return {
            'success': True,
            'updated': updated,
            'result': result,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'result': {},
            'message': f"An error occurred during networkdata_present operation: {str(e)}"
        }

def userdata_present(namespace, bmh_name, pillar_data, userdata_template_path='salt://formulas/bmo/files/cloudinit.j2'):
    """
    Ensure that the userdata ConfigMap in Kubernetes matches the desired state
    defined by pillar data and Jinja2 template. Creates or replaces the ConfigMap if it needs updating.

    Args:
        namespace (str): The namespace of the userdata ConfigMap in Kubernetes.
        bmh_name (str): The name of the Bare Metal Host resource (used for ConfigMap naming).
        pillar_data (dict): Pillar data containing the desired userdata configuration.
        userdata_template_path (str, optional): Salt URI to the Jinja2 template file for userdata.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'result' (dict), and 'message' (str for status or error).

    CLI Example:
        salt '*' kinetic-k8s.userdata_present baremetal-operator-system compute-133-26 pillar_data
    """
    try:
        updated = False
        result = {}
        exists = False
        matches = False
        current_userdata = {}
        desired_userdata = {}
        differences = {}

        # Load Kubernetes configuration for updates
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()

        # Step 1: Retrieve the existing userdata ConfigMap from Kubernetes
        if 'network' in pillar_data:
            try:
                userdata_name = f"{bmh_name}-user-data"
                userdata_cm = core_v1_api.read_namespaced_config_map(name=userdata_name, namespace=namespace)
                exists = True
                current_userdata = userdata_cm.data if userdata_cm.data else {}
            except ApiException as ue:
                exists = False
                current_userdata = {}
                message = f"Userdata ConfigMap {userdata_name} not found: {str(ue)}"
            except Exception as ue:
                exists = False
                current_userdata = {}
                message = f"Error fetching userdata: {str(ue)}"
        else:
            exists = False
            current_userdata = {}
            message = f"Userdata not applicable for {bmh_name}"

        # Step 2: Render the desired userdata configuration from pillar data using Jinja2 template in memory
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
                try:
                    userdata_content = __salt__['cp.get_file_str'](userdata_template_path)
                    if not userdata_content:
                        raise Exception(f"Failed to read userdata template from {userdata_template_path}: Content is empty or inaccessible. Verify the path exists in Salt file roots.")
                    # Strip shebang line if present to avoid rendering issues
                    if userdata_content.startswith('#!'):
                        userdata_content_lines = userdata_content.splitlines()
                        userdata_content = '\n'.join(userdata_content_lines[1:]) if len(userdata_content_lines) > 1 else ''
                        if not userdata_content:
                            raise Exception(f"Userdata template at {userdata_template_path} is empty after removing shebang line.")
                except Exception as file_error:
                    return {
                        'success': False,
                        'updated': False,
                        'result': {'error': str(file_error)},
                        'message': f"Failed to retrieve userdata template file from {userdata_template_path}: {str(file_error)}. Check if the file exists in Salt file roots."
                    }

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
                if exists:
                    current_userdata_data = current_userdata
                    if isinstance(current_userdata, dict) and 'cloud-config' in current_userdata:
                        current_userdata_data = current_userdata.get('cloud-config', '')
                    elif isinstance(current_userdata, dict) and len(current_userdata) == 1:
                        current_userdata_data = list(current_userdata.values())[0]

                    desired_userdata_data = desired_userdata.get('cloud-config', '')
                    if current_userdata_data != desired_userdata_data:
                        differences['cloud-config'] = {
                            'current': current_userdata_data if current_userdata_data else 'not set',
                            'desired': desired_userdata_data
                        }
                    matches = len(differences) == 0
                else:
                    matches = False
            except Exception as userdata_render_error:
                return {
                    'success': False,
                    'updated': False,
                    'result': {'error': str(userdata_render_error)},
                    'message': f"Failed to render userdata template: {str(userdata_render_error)}"
                }
        else:
            desired_userdata = {}
            matches = False
            message = f"Userdata not applicable for {bmh_name}"

        # Step 3: Update or create userdata ConfigMap if it doesn't exist or doesn't match
        if 'network' in pillar_data and (not exists or not matches):
            try:
                userdata_name = f"{bmh_name}-user-data"
                userdata_str = desired_userdata.get('cloud-config', '')
                body = client.V1ConfigMap(
                    metadata=client.V1ObjectMeta(name=userdata_name, namespace=namespace),
                    data={'cloud-config': userdata_str}
                )

                if exists:
                    result = core_v1_api.replace_namespaced_config_map(
                        name=userdata_name,
                        namespace=namespace,
                        body=body
                    )
                    updated = True
                    message = f"Userdata ConfigMap {userdata_name} updated"
                else:
                    result = core_v1_api.create_namespaced_config_map(
                        namespace=namespace,
                        body=body
                    )
                    updated = True
                    message = f"Userdata ConfigMap {userdata_name} created"
            except ApiException as e:
                updated = False
                message = f"Failed to update/create userdata ConfigMap {userdata_name}: {str(e)}"
                result = {'error': str(e)}
        else:
            message = f"Userdata for {bmh_name} already matches desired state or not applicable"
            result = current_userdata

        return {
            'success': True,
            'updated': updated,
            'result': result,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'result': {},
            'message': f"An error occurred during userdata_present operation: {str(e)}"
        }

def bmc_auth_present(namespace, ipmi-password, secret_name='bmc-auth', bmc_auth_template_path='salt://formulas/bmo/files/bmc-auth.j2'):
    """
    Ensure that the bmc-auth Secret in Kubernetes matches the desired state defined by pillar data
    and Jinja2 template. Creates the Secret if it doesn't exist, or updates it if it differs.

    Args:
        namespace (str): The namespace of the Secret in Kubernetes.
        secret_name (str, optional): The name of the Secret. Defaults to 'bmc-auth'.
        bmc_auth_template_path (str, optional): Salt URI to the Jinja2 template file for bmc-auth Secret.
            Defaults to the standard bmc-auth template location.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'result' (dict), and 'message' (str for status or error).

    CLI Example:
        salt '*' kinetic-k8s.bmc_auth_present baremetal-operator-system
    """
    try:
        updated = False
        result = {}
        exists = False
        matches = False
        current_secret = {}
        desired_secret = {}
        differences = {}

        # Load Kubernetes configuration for updates
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        core_v1_api = client.CoreV1Api()

        # Step 1: Retrieve the existing bmc-auth Secret from Kubernetes
        try:
            secret = core_v1_api.read_namespaced_secret(name=secret_name, namespace=namespace)
            exists = True
            current_secret = secret.string_data if secret.string_data else {}
            if not current_secret and secret.data:
                # If string_data is not available, decode data (base64 encoded)
                import base64
                current_secret = {k: base64.b64decode(v).decode('utf-8') for k, v in secret.data.items()}
            message = f"Secret {secret_name} found in namespace {namespace}"
        except ApiException as e:
            exists = False
            current_secret = {}
            message = f"Secret {secret_name} not found in namespace {namespace}: {str(e)}"
        except Exception as e:
            exists = False
            current_secret = {}
            message = f"Error fetching Secret {secret_name}: {str(e)}"

        # Step 2: Render the desired bmc-auth Secret configuration from pillar data using Jinja2 template in memory
        try:
            # Fetch pillar data for rendering
            bmc_auth_context = {
                'pillar': {
                    'bmo_namespace': namespace,
                    'ipmi_password': ipmi-password
                }
            }

            # Use Salt's in-memory rendering for bmc-auth template
            try:
                bmc_auth_content = __salt__['cp.get_file_str'](bmc_auth_template_path)
                if not bmc_auth_content:
                    raise Exception(f"Failed to read bmc-auth template from {bmc_auth_template_path}: Content is empty or inaccessible. Verify the path exists in Salt file roots.")
                # Strip shebang line if present to avoid rendering issues
                if bmc_auth_content.startswith('#!'):
                    bmc_auth_content_lines = bmc_auth_content.splitlines()
                    bmc_auth_content = '\n'.join(bmc_auth_content_lines[1:]) if len(bmc_auth_content_lines) > 1 else ''
                    if not bmc_auth_content:
                        raise Exception(f"bmc-auth template at {bmc_auth_template_path} is empty after removing shebang line.")
            except Exception as file_error:
                return {
                    'success': False,
                    'updated': False,
                    'result': {'error': str(file_error)},
                    'message': f"Failed to retrieve bmc-auth template file from {bmc_auth_template_path}: {str(file_error)}. Check if the file exists in Salt file roots."
                }

            rendered_bmc_auth = __salt__['slsutil.renderer'](
                string=bmc_auth_content,
                default_renderer='jinja|yaml',
                context=bmc_auth_context
            )

            if not rendered_bmc_auth:
                raise Exception("Failed to render bmc-auth template: Empty or invalid output")

            # Handle the case where rendered_bmc_auth is already a dictionary (parsed YAML)
            import yaml
            if isinstance(rendered_bmc_auth, dict):
                desired_secret_full = rendered_bmc_auth
            else:
                # If it's a string, parse it as YAML
                desired_secret_full = yaml.safe_load(rendered_bmc_auth)

            # Extract the stringData from the desired Secret for comparison
            desired_secret = desired_secret_full.get('stringData', {})

            # Compare the existing Secret with the desired Secret
            if exists:
                for key in desired_secret:
                    if key not in current_secret or current_secret[key] != desired_secret[key]:
                        differences[key] = {
                            'current': current_secret.get(key, 'not set'),
                            'desired': desired_secret[key]
                        }
                matches = len(differences) == 0
            else:
                matches = False
        except Exception as bmc_auth_render_error:
            return {
                'success': False,
                'updated': False,
                'result': {'error': str(bmc_auth_render_error)},
                'message': f"Failed to render bmc-auth template: {str(bmc_auth_render_error)}"
            }

        # Step 3: Update or create bmc-auth Secret if it doesn't exist or doesn't match
        if not exists or not matches:
            try:
                body = client.V1Secret(
                    metadata=client.V1ObjectMeta(name=secret_name, namespace=namespace),
                    string_data=desired_secret,
                    type=desired_secret_full.get('type', 'Opaque')
                )

                if exists:
                    result = core_v1_api.replace_namespaced_secret(
                        name=secret_name,
                        namespace=namespace,
                        body=body
                    )
                    updated = True
                    message = f"Secret {secret_name} updated in namespace {namespace}"
                else:
                    result = core_v1_api.create_namespaced_secret(
                        namespace=namespace,
                        body=body
                    )
                    updated = True
                    message = f"Secret {secret_name} created in namespace {namespace}"

                # Step 4: Verify the Secret exists after creation/update
                try:
                    verified_secret = core_v1_api.read_namespaced_secret(name=secret_name, namespace=namespace)
                    if verified_secret:
                        message += f"; Verified Secret {secret_name} exists in namespace {namespace}"
                    else:
                        message += f"; WARNING: Secret {secret_name} reported as created/updated but verification returned empty result"
                        updated = False
                        result = {'error': 'Verification returned empty result'}
                except ApiException as verify_error:
                    message += f"; WARNING: Failed to verify Secret {secret_name} after creation/update: {str(verify_error)}"
                    updated = False
                    result = {'error': str(verify_error)}
            except ApiException as e:
                updated = False
                message = f"Failed to update/create Secret {secret_name}: {str(e)}"
                result = {'error': str(e)}
        else:
            message = f"Secret {secret_name} already matches desired state in namespace {namespace}"
            result = current_secret

        return {
            'success': True if updated or matches else False,
            'updated': updated,
            'result': result,
            'message': message
        }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'result': {},
            'message': f"An error occurred during bmc_auth_present operation: {str(e)}"
        }