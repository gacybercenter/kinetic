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


def ceph_object_store_user_present(
    name,
    namespace,
    store,
    display_name=None,
    cluster_namespace=None,
    capabilities=None,
    quotas=None,
    op_mask=None,
):
    """
    Ensure a Ceph RGW user exists via Rook's CephObjectStoreUser CRD.

    Rook's operator creates the RGW user directly and writes the resulting
    S3 access/secret key pair into a Kubernetes secret named
    ``rook-ceph-object-user-<store>-<name>`` in `namespace`. No admin
    credentials or API signing are needed from Salt for this.

    name
        The CephObjectStoreUser resource name (becomes the RGW uid).

    namespace
        Namespace to create the CephObjectStoreUser in.

    store
        The CephObjectStore this user belongs to.

    display_name
        Optional display name. Defaults to name.

    cluster_namespace
        Namespace of the parent CephCluster/CephObjectStore, if different
        from `namespace`.

    capabilities
        Optional dict of admin capabilities, e.g. {"user": "*", "buckets": "*"}.
        Per Rook, capabilities can only be set at creation time - changing
        them requires deleting and re-creating the CephObjectStoreUser.

    quotas
        Optional dict, e.g. {"maxBuckets": 100, "maxSize": "10G", "maxObjects": 10000}.

    op_mask
        Optional list of allowed RGW operations, e.g. ["read", "write", "delete"].

    Note: this does NOT support subusers or a Swift "temp URL key" - use
    rook.rgw_subuser_present (Ceph Mgr Dashboard API) for subusers;
    temp-url-key remains radosgw-admin CLI only.

    Example:
    .. code-block:: yaml

        glance_rgw_user:
          rook.ceph_object_store_user_present:
            - name: glance
            - namespace: rook-ceph
            - store: rsc-object-store
            - display_name: glance
            - require:
              - rook: deploy_ceph_object_store
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_rook.ceph_object_store_user_present"](
            name=name,
            namespace=namespace,
            store=store,
            display_name=display_name,
            cluster_namespace=cluster_namespace,
            capabilities=capabilities,
            quotas=quotas,
            op_mask=op_mask,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"ceph_object_store_user_updated": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure CephObjectStoreUser {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def rgw_subuser_present(uid, subuser, dashboard_endpoint, dashboard_username, dashboard_password,
                        access="full", generate_secret=True, secret=None,
                        verify_ssl=True, **kwargs):
    """
    Ensure an RGW subuser exists under the given uid, via the Ceph Mgr
    Dashboard REST API (JWT bearer-token auth - no request signing or
    extra pip dependency required).

    Requires the Dashboard module to already be linked to RGW (one-time
    setup, not automated by Rook):

    .. code-block:: bash

        ceph dashboard set-rgw-api-access-key -i <accesskeyfile>
        ceph dashboard set-rgw-api-secret-key -i <secretkeyfile>
        ceph dashboard set-rgw-api-host <rgw-service>
        ceph dashboard set-rgw-api-port <port>
        ceph dashboard set-rgw-api-scheme http

    uid
        Parent user ID (must already exist, e.g. via
        rook.ceph_object_store_user_present).

    subuser
        Subuser name (e.g. "glance:swift").

    dashboard_endpoint
        Base URL of the Ceph Mgr Dashboard (e.g.
        "https://rook-ceph-mgr-dashboard.rook-ceph.svc:8443").

    dashboard_username / dashboard_password
        Credentials of a Dashboard user with RGW management permissions.

    access
        Access level (read, write, readwrite, full).

    generate_secret / secret
        Same semantics as keys above.

    verify_ssl
        Whether to verify TLS certificates when calling the endpoint.

    Note: this does NOT support setting a Swift "temp URL key" - not
    exposed by the Dashboard API's RgwUser endpoints, only by the
    radosgw-admin CLI.

    Example:
    .. code-block:: yaml

        glance_rgw_subuser:
          rook.rgw_subuser_present:
            - uid: glance
            - subuser: glance:swift
            - access: full
            - generate_secret: true
            - dashboard_endpoint: https://rook-ceph-mgr-dashboard.rook-ceph.svc:8443
            - dashboard_username: admin
            - dashboard_password: {{ pillar['osh']['ceph_dashboard_password'] }}
            - require:
              - rook: glance_rgw_user
    """
    ret = _state_ret(subuser)

    try:
        result = __salt__["kinetic_rook.rgw_subuser_present"](
            uid=uid,
            subuser=subuser,
            dashboard_endpoint=dashboard_endpoint,
            dashboard_username=dashboard_username,
            dashboard_password=dashboard_password,
            access=access,
            generate_secret=generate_secret,
            secret=secret,
            verify_ssl=verify_ssl,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"rgw_subuser_updated": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure RGW subuser {subuser}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def ceph_object_store_present(
    name,
    namespace,
    replicas=1,
    port=80,
    ssl_enabled=False,
    annotations=None,
    gateway_instances=1,
    gateway_resources=None,
    enable_swift_api=True,
    swift_port=8080,
    swift_account_in_url=True,
    swift_url_prefix="swift",
    enable_s3_api=True,
    preserve_pools_on_delete=True,
    auth_keystone=False,
    keystone_url="",
    keystone_accepted_roles=None,
    keystone_implicit_tenants="swift",
    keystone_revocation_interval=1200,
    keystone_service_user_secret_name="usersecret",
    keystone_token_cache_size=1000,
    rgw_keystone_api_version="3",
    rgw_keystone_implicit_tenants="true",
    rgw_s3_auth_use_keystone="true",
    debug_rgw="0",
):
    """
    Ensure a Ceph Object Store (RGW - RADOS Gateway) exists in the specified Kubernetes namespace using Rook.

    name
        The name of the state (arbitrary, for SaltStack identification) and the Ceph Object Store resource.

    namespace
        The Kubernetes namespace for the Ceph Object Store (typically the Rook namespace).

    replicas
        Optional. Number of RGW replicas for high availability. Defaults to 1.

    port
        Optional. Port for the RGW service (S3 API). Defaults to 80.

    ssl_enabled
        Optional. Enable SSL for RGW service. Defaults to False.

    annotations
        Optional. Additional annotations for the Ceph Object Store resource. Defaults to None.

    gateway_instances
        Optional. Number of gateway instances. Defaults to 1.

    gateway_resources
        Optional. Resource limits and requests for gateway pods as a dictionary. Defaults to None.

    enable_swift_api
        Optional. Enable Swift API compatibility for the object store. Defaults to True.

    swift_port
        Optional. Port for Swift API if enabled. Defaults to 8080.

    swift_account_in_url
        Optional. Include account in Swift URL structure. Defaults to True.

    swift_url_prefix
        Optional. URL prefix for Swift API. Defaults to "swift".

    enable_s3_api
        Optional. Enable S3 API compatibility (default in RGW). Defaults to True.

    preserve_pools_on_delete
        Optional. Preserve metadata and data pools when deleting the object store. Defaults to True.

    auth_keystone
        Optional. Enable Keystone authentication integration. Defaults to False.

    keystone_url
        Optional. URL for Keystone authentication service. Defaults to "".

    keystone_accepted_roles
        Optional. List of roles accepted by Keystone for access. Defaults to None (uses ["admin", "member", "service"] if auth_keystone is True).

    keystone_implicit_tenants
        Optional. Implicit tenant handling for Keystone (e.g., "swift"). Defaults to "swift".

    keystone_revocation_interval
        Optional. Token revocation check interval in seconds. Defaults to 1200.

    keystone_service_user_secret_name
        Mandatory if auth_keystone is True. Name of the secret containing Keystone service user credentials. Defaults to "usersecret".

    rgw_keystone_api_version
        Optional. Keystone API version for RGW authentication. Defaults to "3".

    rgw_keystone_implicit_tenants
        Optional. Enable implicit tenants for Keystone-Swift integration. Defaults to "true".

    rgw_s3_auth_use_keystone
        Optional. Use Keystone for S3 authentication. Defaults to "true".

    debug_rgw
        Optional. Debug level for RGW (e.g., "15" for detailed logging). Defaults to "0" (no debugging).

    keystone_token_cache_size
        Optional. Size of token cache for Keystone authentication. Defaults to 1000.

    Example:
    .. code-block:: yaml

        ensure_ceph_object_store:
          rook.ceph_object_store_present:
            - name: my-object-store
            - namespace: rook-ceph
            - replicas: 3
            - port: 80
            - ssl_enabled: false
            - gateway_instances: 2
            - enable_swift_api: true
            - swift_port: 8080
            - swift_account_in_url: true
            - swift_url_prefix: "swift"
            - enable_s3_api: true
            - preserve_pools_on_delete: true
            - auth_keystone: true
            - keystone_url: "https://keystone.rook-ceph.svc/"
            - keystone_accepted_roles:
                - admin
                - member
                - service
            - keystone_implicit_tenants: "swift"
            - keystone_revocation_interval: 1200
            - keystone_service_user_secret_name: "usersecret"
            - keystone_token_cache_size: 1000
            - rgw_keystone_api_version: "3"
            - rgw_keystone_implicit_tenants: "true"
            - rgw_s3_auth_use_keystone: "true"
            - debug_rgw: "15"
            - gateway_resources:
                limits:
                  cpu: "500m"
                  memory: "512Mi"
                requests:
                  cpu: "200m"
                  memory: "256Mi"
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_rook.ceph_object_store_present"](
            name=name,
            namespace=namespace,
            replicas=replicas,
            port=port,
            ssl_enabled=ssl_enabled,
            annotations=annotations,
            gateway_instances=gateway_instances,
            gateway_resources=gateway_resources,
            enable_swift_api=enable_swift_api,
            swift_port=swift_port,
            swift_account_in_url=swift_account_in_url,
            swift_url_prefix=swift_url_prefix,
            enable_s3_api=enable_s3_api,
            preserve_pools_on_delete=preserve_pools_on_delete,
            auth_keystone=auth_keystone,
            keystone_url=keystone_url,
            keystone_accepted_roles=keystone_accepted_roles,
            keystone_implicit_tenants=keystone_implicit_tenants,
            keystone_revocation_interval=keystone_revocation_interval,
            keystone_service_user_secret_name=keystone_service_user_secret_name,
            keystone_token_cache_size=keystone_token_cache_size,
            rgw_keystone_api_version=rgw_keystone_api_version,
            rgw_keystone_implicit_tenants=rgw_keystone_implicit_tenants,
            rgw_s3_auth_use_keystone=rgw_s3_auth_use_keystone,
            debug_rgw=debug_rgw,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")

        if result.get("updated", False):
            ret["changes"] = {"ceph_object_store_updated": True}
        else:
            ret["changes"] = {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure CephObjectStore {name} in namespace {namespace}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret
