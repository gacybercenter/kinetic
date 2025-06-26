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
            Defaults to the standard BMH template location.
        network_template_path (str, optional): Salt URI to the Jinja2 template file for network data.
            Defaults to the standard network data template location.
        userdata_template_path (str, optional): Salt URI to the Jinja2 template file for userdata.
            Defaults to the standard userdata template location.

    Returns:
        dict: A dictionary with 'success' (bool), 'bmh_updated' (bool), 'network_updated' (bool), 'userdata_updated' (bool),
              'bmh_result' (dict), 'network_result' (dict), 'userdata_result' (dict), and 'message' (str for status or error).

    CLI Example:
        salt '*' kinetic-k8s.bmh_replace baremetal-operator-system compute-133-26 pillar_data
    """
    try:
        # Step 1: Compare the current state with the desired state
        compare_result = compare_bmh(
            namespace=namespace,
            bmh_name=bmh_name,
            pillar_data=pillar_data,
            bmh_template_path=bmh_template_path,
            network_template_path=network_template_path,
            userdata_template_path=userdata_template_path
        )

        if not compare_result['success']:
            return {
                'success': False,
                'bmh_updated': False,
                'network_updated': False,
                'userdata_updated': False,
                'bmh_result': {},
                'network_result': {},
                'userdata_result': {},
                'message': f"Failed to compare current state: {compare_result['message']}"
            }

        bmh_updated = False
        network_updated = False
        userdata_updated = False
        bmh_result = {}
        network_result = {}
        userdata_result = {}

        # Load Kubernetes configuration for updates
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        core_v1_api = client.CoreV1Api()

        # Step 2: Update or create network data ConfigMap if it doesn't exist or doesn't match
        if 'network' in pillar_data and (not compare_result['network_exists'] or not compare_result['network_matches']):
            try:
                network_data_name = f"{bmh_name}-network-data"
                # Convert desired network data to a string if needed for ConfigMap
                import json
                network_data_str = json.dumps(compare_result['desired_network'])
                body = client.V1ConfigMap(
                    metadata=client.V1ObjectMeta(name=network_data_name, namespace=namespace),
                    data={'networkData': network_data_str}
                )

                if compare_result['network_exists']:
                    # Replace existing ConfigMap
                    network_result = core_v1_api.replace_namespaced_config_map(
                        name=network_data_name,
                        namespace=namespace,
                        body=body
                    )
                    network_updated = True
                    network_message = f"Network data ConfigMap {network_data_name} updated"
                else:
                    # Create new ConfigMap
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
            network_result = compare_result['current_network']

        # Step 3: Update or create userdata ConfigMap if it doesn't exist or doesn't match
        if 'network' in pillar_data and (not compare_result['userdata_exists'] or not compare_result['userdata_matches']):
            try:
                userdata_name = f"{bmh_name}-user-data"
                userdata_str = compare_result['desired_userdata'].get('cloud-config', '')
                body = client.V1ConfigMap(
                    metadata=client.V1ObjectMeta(name=userdata_name, namespace=namespace),
                    data={'cloud-config': userdata_str}
                )

                if compare_result['userdata_exists']:
                    # Replace existing ConfigMap
                    userdata_result = core_v1_api.replace_namespaced_config_map(
                        name=userdata_name,
                        namespace=namespace,
                        body=body
                    )
                    userdata_updated = True
                    userdata_message = f"Userdata ConfigMap {userdata_name} updated"
                else:
                    # Create new ConfigMap
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
            userdata_result = compare_result['current_userdata']

        # Step 4: Delete and recreate BMH if it doesn't exist, doesn't match, or if network/userdata were updated
        if not compare_result['bmh_exists'] or not compare_result['bmh_matches'] or network_updated or userdata_updated:
            try:
                group = "metal3.io"
                version = "v1alpha1"
                plural = "baremetalhosts"
                body = compare_result['desired_bmh']

                if compare_result['bmh_exists']:
                    # Delete existing BMH
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

                # Create new BMH (whether it existed before or not)
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
            bmh_result = compare_result['current_bmh']

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