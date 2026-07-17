# -*- coding: utf-8 -*-
"""
SaltStack execution module for Rook Ceph management.

This module provides functions to manage Rook Ceph Custom Resources directly,
rather than through Helm charts. It follows the pattern established in kinetic-k8s.py.
"""

import json
import salt.utils.decorators as decorators
from kubernetes import client, config
from kubernetes.client.rest import ApiException

__virtualname__ = "kinetic_rook"


@decorators.memoize
def __virtual__():
    """
    Check if the kubernetes python library is available.
    """
    try:
        from kubernetes import client
        return "kinetic_rook"
    except ImportError:
        return (
            False,
            'The kubernetes python library is not installed. '
            'Please install it using "pip install kubernetes".'
        )


def _load_k8s_config():
    """Load Kubernetes configuration, preferring in-cluster config then kubeconfig."""
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()


def ceph_cluster_present(
    namespace="rook-ceph",
    name="rook-ceph",
    ceph_version="quay.io/ceph/ceph:v18.2.4",
    devices=None,
    use_all_devices=False,
    network_provider="host",
    public_network=None,
    cluster_network=None,
    dashboard_enabled=True,
    monitoring_enabled=True,
    toolbox_enabled=True,
    spec=None,
):
    """
    Ensure a CephCluster Custom Resource exists with the specified configuration.

    This is a high-level function that builds a reasonable CephCluster spec from
    common parameters. For full control, pass a complete  dictionary.

    Args:
        namespace (str): Namespace for the CephCluster (default: rook-ceph)
        name (str): Name of the CephCluster (default: rook-ceph)
        ceph_version (str): Ceph container image (default: latest v18)
        devices (list): List of device paths to use for OSDs
        use_all_devices (bool): Whether to use all available devices
        network_provider (str): Network provider ('host' or 'multus')
        public_network (str): CIDR for public network (if not using host network)
        cluster_network (str): CIDR for cluster network (if not using host network)
        dashboard_enabled (bool): Enable Ceph dashboard
        monitoring_enabled (bool): Enable Prometheus monitoring
        toolbox_enabled (bool): Deploy debug toolbox pod
        spec (dict, optional): Complete spec to override all other parameters

    Returns:
        dict: success, updated, message
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "ceph.rook.io"
        version = "v1"
        plural = "cephclusters"

        # If user provided full spec, use it
        if spec is None:
            spec = {
                "cephVersion": {
                    "image": ceph_version,
                    "allowUnsupported": False
                },
                "dataDirHostPath": "/var/lib/rook",
                "dashboard": {
                    "enabled": dashboard_enabled,
                    "ssl": True,
                    "urlPrefix": "/"
                },
                "monitoring": {
                    "enabled": monitoring_enabled
                },
                "network": {
                    "provider": network_provider
                },
                "storage": {
                    "useAllNodes": True,
                    "useAllDevices": use_all_devices,
                },
                "placement": {
                    "all": {
                        "tolerations": [{
                            "key": "node-role.kubernetes.io/rook-node",
                            "operator": "Exists",
                            "effect": "NoSchedule"
                        }]
                    }
                }
            }

            # Add device configuration
            if devices:
                spec["storage"]["devices"] = [{"name": d} for d in devices]
            elif use_all_devices:
                spec["storage"]["useAllDevices"] = True

            # Add network configuration
            if network_provider == "host":
                spec["network"]["provider"] = "host"
            elif public_network and cluster_network:
                spec["network"]["provider"] = "multus"
                spec["network"]["selectors"] = {
                    "public": public_network,
                    "cluster": cluster_network
                }

            # Add toolbox if requested
            if toolbox_enabled:
                spec["toolbox"] = {"enabled": True}
        else:
            spec = dict(spec)  # avoid mutating original

        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "CephCluster",
            "metadata": {"name": name, "namespace": namespace},
            "spec": spec,
        }

        exists = False
        updated = False
        matches = False
        resource = None

        # Check if CephCluster exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=name,
            )
            exists = True
            current_spec = resource.get("spec", {})
            if current_spec == spec:
                matches = True
                message = f"CephCluster {name} already exists and matches desired spec"
            else:
                matches = False
                message = f"CephCluster {name} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"CephCluster {name} does not exist"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking CephCluster {name}: {str(e)[:80]}...",
                }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=body,
                )
                updated = True
                message = f"CephCluster {name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create CephCluster {name}: {str(e)[:100]}...",
                }
        elif not matches:
            try:
                if (
                    resource
                    and "metadata" in resource
                    and "resourceVersion" in resource["metadata"]
                ):
                    body["metadata"]["resourceVersion"] = resource["metadata"]["resourceVersion"]
                custom_api.replace_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    name=name,
                    body=body,
                )
                updated = True
                message = f"CephCluster {name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update CephCluster {name}: {str(e)[:100]}...",
                }
        else:
            message = f"CephCluster {name} in namespace {namespace} already exists and matches desired state"

        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure CephCluster {name}: {str(e)}",
        }
