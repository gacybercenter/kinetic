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