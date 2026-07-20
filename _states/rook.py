# -*- coding: utf-8 -*-
"""
SaltStack state module for Rook Ceph management.

This module provides states to manage Rook Ceph Custom Resources directly.
It complements the existing k8s module by providing Rook-specific states.
"""

def __virtual__():
    """
    Only load if the kinetic_rook execution module is available.
    """
    if "kinetic_rook.ceph_cluster_present" in __salt__:
        return "rook"
    return (
        False,
        "The kinetic_rook execution module is not available."
    )


def _state_ret(name):
    """Return a standard SaltStack state return dict."""
    return {"name": name, "result": False, "comment": "", "changes": {}}


def ceph_cluster_present(
    name,
    namespace="rook-ceph",
    ceph_version="quay.io/ceph/ceph:v18.2.4",
    use_all_devices=False,
    use_all_nodes=True,
    device_filter=None,         # e.g. "^sd." or "nvme.*"
    network_provider="host",
    public_network=None,
    cluster_network=None,
    dashboard_enabled=True,
    monitoring_enabled=True,
    toolbox_enabled=True,
    placement=None,
    placement_pillar=None,
    spec=None,
):
    """
    Ensure a CephCluster Custom Resource is present with the given configuration.

    This state uses the  execution module.
    It provides a high-level, easy-to-use interface for common CephCluster setups.

    name
        The name of the state.

    namespace
        Namespace for the CephCluster (default: rook-ceph).

    ceph_version
        Full Ceph container image (e.g. quay.io/ceph/ceph:v18.2.4).

    use_all_devices
        Whether to use all available devices for OSDs.

    use_all_nodes
        Whether to use all nodes in the cluster (default: True).

    device_filter
        Regex filter for devices (e.g. "^sd." or "nvme.*").

    network_provider
        Usually 'host'. Can be 'multus' if public_network and cluster_network are set.

    public_network, cluster_network
        CIDR ranges for public and cluster traffic (used with multus).

    dashboard_enabled, monitoring_enabled, toolbox_enabled
        Feature flags for common Ceph components.

    placement
        Direct placement configuration (affinity, tolerations, etc.)

    placement_pillar
        Pillar key containing placement configuration. If a component is named 'node',
        it will be automatically mapped to 'all' (Rook convention).

    spec
        Full CephCluster .spec dictionary. Overrides all other parameters if provided.

    Example:
    .. code-block:: yaml

        rook_cluster:
          rook.ceph_cluster_present:
            - name: rook-ceph
            - namespace: rook-ceph
            - ceph_version: quay.io/ceph/ceph:v18.2.4
            - osd_mappings:
                storage:
                  nodes:
                    - storage-01:
                        device_filter: "^sd."
                    - storage-02:
                        device_filter: "^sd."
            - dashboard_enabled: True
            - monitoring_enabled: True
            - network_provider: host
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_rook.ceph_cluster_present"](
            namespace=namespace,
            name=name,
            ceph_version=ceph_version,
            use_all_devices=use_all_devices,
            use_all_nodes=use_all_nodes,
            device_filter=device_filter,
            network_provider=network_provider,
            public_network=public_network,
            cluster_network=cluster_network,
            dashboard_enabled=dashboard_enabled,
            monitoring_enabled=monitoring_enabled,
            toolbox_enabled=toolbox_enabled,
            placement=placement,
            placement_pillar=placement_pillar,
            spec=spec,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"ceph_cluster_updated": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure CephCluster {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret
