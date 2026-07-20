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
    placement=None,
    placement_pillar=None,  # Pillar key containing component placements (e.g. 'rook:placement')
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
        public_network (str): For Multus, use "namespace/nadname" format (e.g. "default/public")
        cluster_network (str): For Multus, use "namespace/nadname" format (e.g. "default/cluster")
        dashboard_enabled (bool): Enable Ceph dashboard
        monitoring_enabled (bool): Enable Prometheus monitoring
        toolbox_enabled (bool): Deploy debug toolbox pod
        placement (dict, optional): Direct placement configuration (affinity, tolerations, etc.)
        placement_pillar (str, optional): Pillar key containing placement config
            (e.g. 'rook:placement' or 'ceph:placement'). If a component is named 'node',
            it will be mapped to 'all' as per Rook conventions.
        spec (dict, optional): Complete spec to override all other parameters

    Returns:
        dict: success, updated, message
    """
    try:
        _load_k8s_config()

        # Load placement from pillar if placement_pillar is provided
        if placement_pillar and not placement:
            placement = __salt__['pillar.get'](placement_pillar, {})

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
                    "useAllNodes": False,
                    "useAllDevices": use_all_devices,
                    "onlyApplyOSDPlacement": True
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
                # Rook Multus expects "namespace/nadname" format (e.g. "default/public")
                # If only NAD name is provided without namespace, assume "default"
                def _format_multus_net(net):
                    if isinstance(net, str) and "/" not in net:
                        return f"default/{net}"
                    return net

                spec["network"]["selectors"] = {
                    "public": _format_multus_net(public_network),
                    "cluster": _format_multus_net(cluster_network)
                }

            # Add toolbox if requested
            if toolbox_enabled:
                spec["toolbox"] = {"enabled": True}

            # Add placement configuration with 'node' -> 'all' mapping
            if placement:
                placement_dict = dict(placement)  # copy to avoid mutation
                if "node" in placement_dict and "all" not in placement_dict:
                    placement_dict["all"] = placement_dict.pop("node")
                spec["placement"] = placement_dict
            else:
                # Default sensible placement for production
                spec["placement"] = {
                    "all": {
                        "tolerations": [{
                            "key": "node-role.kubernetes.io/rook-node",
                            "operator": "Exists",
                            "effect": "NoSchedule"
                        }]
                    }
                }
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
