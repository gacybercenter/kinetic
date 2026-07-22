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
    only_apply_osd_placement=False,
    metadata_device=None,       # Dedicated device for metadata (e.g. "md0", "nvme0n1")
    network_provider="host",
    public_network=None,
    cluster_network=None,
    dashboard_enabled=True,
    monitoring_enabled=True,
    toolbox_enabled=True,
    resources=None,         # Per-daemon resource limits/requests from pillar
    resources_pillar=None,  # Pillar key for resources (e.g. 'res-k8s:rook:resources')
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

    only_apply_osd_placement
        Whether placement rules should only apply to OSDs (default: False).

    metadata_device
        Dedicated device for Ceph metadata (e.g. "md0", "nvme0n1").

    network_provider
        Usually 'host'. Can be 'multus' if public_network and cluster_network are set.

    public_network, cluster_network
        For host provider: CIDR ranges (string or list).
        For multus: "namespace/nadname" format (e.g. "default/public").

    dashboard_enabled, monitoring_enabled, toolbox_enabled
        Feature flags for common Ceph components.

    resources
        Per-daemon resource limits/requests. Example (under res-k8s:rook:resources):
          mon:
            limits:
              cpu: "2"
              memory: "2Gi"
            requests:
              cpu: "1"
              memory: "512Mi"
          osd:
            limits:
              cpu: "4"
              memory: "8Gi"

    resources_pillar
        Pillar key for resources (e.g. 'res-k8s:rook:resources')

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
            only_apply_osd_placement=only_apply_osd_placement,
            metadata_device=metadata_device,
            resources=resources,
            resources_pillar=resources_pillar,
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


def ceph_blockpool_present(
    name,
    namespace="rook-ceph",
    failure_domain="host",
    replicated_size=3,
    spec=None,
):
    """
    Ensure a CephBlockPool Custom Resource exists.

    name
        Name of the block pool.

    namespace
        Namespace for the CephBlockPool.

    failure_domain
        Failure domain (host, osd, etc.).

    replicated_size
        Number of replicas.

    spec
        Full spec to override defaults.

    Example:
    .. code-block:: yaml

        general_pool:
          rook.ceph_blockpool_present:
            - name: general
            - namespace: rook-ceph
            - failure_domain: host
            - replicated_size: 3
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_rook.ceph_blockpool_present"](
            namespace=namespace,
            name=name,
            failure_domain=failure_domain,
            replicated_size=replicated_size,
            spec=spec,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"ceph_blockpool_updated": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure CephBlockPool {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def storageclass_present(
    name="rook-ceph-block",
    provisioner="rook-ceph.rbd.csi.ceph.com",
    parameters=None,
    reclaim_policy="Delete",
    volume_binding_mode="Immediate",
    allow_volume_expansion=True,
    cluster_id="rook-ceph",  # clusterID for Rook CSI driver
    spec=None,
):
    """
    Ensure a StorageClass for Rook Ceph RBD exists.

    name
        Name of the StorageClass.

    provisioner
        CSI provisioner name.

    parameters
        StorageClass parameters.

    reclaim_policy
        Reclaim policy (Delete/Retain).

    volume_binding_mode
        Volume binding mode.

    allow_volume_expansion
        Allow volume expansion.

    spec
        Full spec to override defaults.

    Example:
    .. code-block:: yaml

        rook_ceph_block:
          rook.storageclass_present:
            - name: rook-ceph-block
            - provisioner: rook-ceph.rbd.csi.ceph.com
            - parameters:
                pool: general
                imageFormat: "2"
                imageFeatures: layering,fast-diff,object-map,deep-flatten,exclusive-lock
                csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
                csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
                csi.storage.k8s.io/fstype: ext4
            - reclaim_policy: Delete
            - volume_binding_mode: Immediate
            - allow_volume_expansion: true
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_rook.storageclass_present"](
            name=name,
            provisioner=provisioner,
            parameters=parameters,
            reclaim_policy=reclaim_policy,
            volume_binding_mode=volume_binding_mode,
            allow_volume_expansion=allow_volume_expansion,
            cluster_id=cluster_id,
            spec=spec,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"storageclass_updated": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure StorageClass {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret
