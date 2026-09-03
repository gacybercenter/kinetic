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
    use_all_devices=False,
    use_all_nodes=True,
    device_filter=None,         # e.g. "^sd." or "nvme.*"
    only_apply_osd_placement=False,  # Apply placement rules only to OSDs (default: False)
    metadata_device=None,       # Dedicated device for metadata (e.g. "md0", "nvme0n1")
    network_provider="host",
    public_network=None,
    cluster_network=None,
    dashboard_enabled=True,
    monitoring_enabled=True,
    toolbox_enabled=True,
    resources=None,         # Per-daemon resource limits/requests (or use resources_pillar)
    resources_pillar=None,  # Pillar key for resources (e.g. 'res-k8s:rook:resources')
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
        use_all_devices (bool): Use all devices on nodes for OSDs
        use_all_nodes (bool): Use all nodes in the cluster for Ceph (default: True)
        device_filter (str): Regex to filter devices (e.g. "^sd." or "nvme.*")
        only_apply_osd_placement (bool): Apply placement rules only to OSDs (default: False)
        metadata_device (str): Dedicated device for Ceph metadata (e.g. "md0", "nvme0n1")
        network_provider (str): Network provider ('host' or 'multus')
        public_network (str): For Multus, use "namespace/nadname" format (e.g. "default/public")
        cluster_network (str): For Multus, use "namespace/nadname" format (e.g. "default/cluster")
        dashboard_enabled (bool): Enable Ceph dashboard
        monitoring_enabled (bool): Enable Prometheus monitoring
        toolbox_enabled (bool): Deploy debug toolbox pod
        resources (dict, optional): Per-daemon resource limits/requests.
            Example (under res-k8s:rook:resources):
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
        resources_pillar (str, optional): Pillar key for resources (e.g. 'res-k8s:rook:resources')
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

        # Load resources from pillar if resources_pillar is provided
        if resources_pillar and not resources:
            resources = __salt__['pillar.get'](resources_pillar, {})

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
                    "useAllNodes": use_all_nodes,
                    "useAllDevices": use_all_devices,
                    "onlyApplyOSDPlacement": only_apply_osd_placement
                }
            }

            # Add storage configuration based on new simpler parameters
            if device_filter:
                spec["storage"]["deviceFilter"] = device_filter
            if metadata_device:
                if "config" not in spec["storage"]:
                    spec["storage"]["config"] = {}
                spec["storage"]["config"]["metadataDevice"] = metadata_device
            # Note: nodes configuration can still be provided via full `spec` override if needed

            # Add network configuration
            if network_provider == "host":
                spec["network"]["provider"] = "host"
                # For host networking, use addressRanges as requested
                if public_network or cluster_network:
                    spec["network"]["addressRanges"] = {}
                    if public_network:
                        if isinstance(public_network, str):
                            spec["network"]["addressRanges"]["public"] = [public_network]
                        elif isinstance(public_network, list):
                            spec["network"]["addressRanges"]["public"] = public_network
                    if cluster_network:
                        if isinstance(cluster_network, str):
                            spec["network"]["addressRanges"]["cluster"] = [cluster_network]
                        elif isinstance(cluster_network, list):
                            spec["network"]["addressRanges"]["cluster"] = cluster_network
            elif cluster_network:
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

            # Add per-daemon resource configuration from pillar
            if resources:
                spec["resources"] = resources

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


def ceph_blockpool_present(
    namespace="rook-ceph",
    name="general",
    failure_domain="host",
    replicated_size=3,
    spec=None,
):
    """
    Ensure a CephBlockPool Custom Resource exists.

    Args:
        namespace (str): Namespace for the CephBlockPool
        name (str): Name of the block pool
        failure_domain (str): Failure domain (host, osd, etc.)
        replicated_size (int): Number of replicas
        spec (dict, optional): Full spec to override defaults

    Returns:
        dict: success, updated, message
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "ceph.rook.io"
        version = "v1"
        plural = "cephblockpools"

        if spec is None:
            spec = {
                "failureDomain": failure_domain,
                "replicated": {
                    "size": replicated_size
                }
            }
        else:
            spec = dict(spec)

        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "CephBlockPool",
            "metadata": {"name": name, "namespace": namespace},
            "spec": spec,
        }

        exists = False
        updated = False
        matches = False
        resource = None

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
                message = f"CephBlockPool {name} already exists and matches desired spec"
            else:
                matches = False
                message = f"CephBlockPool {name} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"CephBlockPool {name} does not exist"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking CephBlockPool {name}: {str(e)[:80]}...",
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
                message = f"CephBlockPool {name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create CephBlockPool {name}: {str(e)[:100]}...",
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
                message = f"CephBlockPool {name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update CephBlockPool {name}: {str(e)[:100]}...",
                }
        else:
            message = f"CephBlockPool {name} in namespace {namespace} already exists and matches desired state"

        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure CephBlockPool {name}: {str(e)}",
        }


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

    Args:
        name (str): Name of the StorageClass
        provisioner (str): CSI provisioner name
        parameters (dict): StorageClass parameters
        reclaim_policy (str): Reclaim policy (Delete/Retain)
        volume_binding_mode (str): Volume binding mode
        allow_volume_expansion (bool): Allow volume expansion
        cluster_id (str): clusterID for Rook CSI driver (default: rook-ceph)
        spec (dict, optional): Full spec to override defaults

    Returns:
        dict: success, updated, message
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "storage.k8s.io"
        version = "v1"
        plural = "storageclasses"

        if spec is None:
            if parameters is None:
                parameters = {
                    "pool": "general",
                    "imageFormat": "2",
                    "imageFeatures": "layering,fast-diff,object-map,deep-flatten,exclusive-lock",
                    "csi.storage.k8s.io/provisioner-secret-name": "rook-csi-rbd-provisioner",
                    "csi.storage.k8s.io/provisioner-secret-namespace": "rook-ceph",
                    "csi.storage.k8s.io/controller-expand-secret-name": "rook-csi-rbd-provisioner",
                    "csi.storage.k8s.io/controller-expand-secret-namespace": "rook-ceph",
                    "csi.storage.k8s.io/controller-publish-secret-name": "rook-csi-rbd-provisioner",
                    "csi.storage.k8s.io/controller-publish-secret-namespace": "rook-ceph",
                    "csi.storage.k8s.io/node-stage-secret-name": "rook-csi-rbd-node",
                    "csi.storage.k8s.io/node-stage-secret-namespace": "rook-ceph",
                    "csi.storage.k8s.io/node-publish-secret-name": "rook-csi-rbd-node",
                    "csi.storage.k8s.io/node-publish-secret-namespace": "rook-ceph",
                    "csi.storage.k8s.io/fstype": "ext4",
                    "clusterID": cluster_id  # Configurable via cluster_id parameter
                }

            spec = {
                "provisioner": provisioner,
                "parameters": parameters,
                "reclaimPolicy": reclaim_policy,
                "volumeBindingMode": volume_binding_mode,
                "allowVolumeExpansion": allow_volume_expansion
            }
        else:
            spec = dict(spec)

        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "StorageClass",
            "metadata": {"name": name},
            "provisioner": provisioner,
            "parameters": parameters or spec.get("parameters", {}),
            "reclaimPolicy": reclaim_policy,
            "volumeBindingMode": volume_binding_mode,
            "allowVolumeExpansion": allow_volume_expansion,
        }

        exists = False
        updated = False
        matches = False
        resource = None

        try:
            resource = custom_api.get_cluster_custom_object(
                group=group,
                version=version,
                plural=plural,
                name=name,
            )
            exists = True
            # Simple comparison for StorageClass
            if (
                resource.get("provisioner") == provisioner and
                resource.get("parameters") == parameters
            ):
                matches = True
                message = f"StorageClass {name} already exists and matches desired spec"
            else:
                matches = False
                message = f"StorageClass {name} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"StorageClass {name} does not exist"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking StorageClass {name}: {str(e)[:80]}...",
                }

        if not exists:
            try:
                custom_api.create_cluster_custom_object(
                    group=group,
                    version=version,
                    plural=plural,
                    body=body,
                )
                updated = True
                message = f"StorageClass {name} created"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create StorageClass {name}: {str(e)[:100]}...",
                }
        elif not matches:
            try:
                if (
                    resource
                    and "metadata" in resource
                    and "resourceVersion" in resource["metadata"]
                ):
                    body["metadata"]["resourceVersion"] = resource["metadata"]["resourceVersion"]
                custom_api.replace_cluster_custom_object(
                    group=group,
                    version=version,
                    plural=plural,
                    name=name,
                    body=body,
                )
                updated = True
                message = f"StorageClass {name} updated"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update StorageClass {name}: {str(e)}...",
                }
        else:
            message = f"StorageClass {name} already exists and matches desired state"

        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure StorageClass {name}: {str(e)}",
        }


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
    keystone_service_user_secret_name="",
    keystone_token_cache_size=1000,
    rgw_keystone_api_version="3",
    rgw_keystone_implicit_tenants="true",
    rgw_s3_auth_use_keystone="true",
    debug_rgw="0",
):
    """
    Ensure a Ceph Object Store (RGW - RADOS Gateway) exists in the specified Kubernetes namespace using Rook.

    Args:
        name (str): The name of the Ceph Object Store resource.
        namespace (str): The Kubernetes namespace for the Ceph Object Store (typically the Rook namespace).
        replicas (int, optional): Number of RGW replicas for high availability. Defaults to 1.
        port (int, optional): Port for the RGW service (S3 API). Defaults to 80.
        ssl_enabled (bool, optional): Enable SSL for RGW service. Defaults to False.
        annotations (dict, optional): Additional annotations for the Ceph Object Store resource. Defaults to None.
        gateway_instances (int, optional): Number of gateway instances. Defaults to 1.
        gateway_resources (dict, optional): Resource limits and requests for gateway pods. Defaults to None.
        enable_swift_api (bool, optional): Enable Swift API compatibility for the object store. Defaults to True.
        swift_port (int, optional): Port for Swift API if enabled. Defaults to 8080.
        swift_account_in_url (bool, optional): Include account in Swift URL structure. Defaults to True.
        swift_url_prefix (str, optional): URL prefix for Swift API. Defaults to "swift".
        enable_s3_api (bool, optional): Enable S3 API compatibility (default in RGW). Defaults to True.
        preserve_pools_on_delete (bool, optional): Preserve metadata and data pools when deleting the object store. Defaults to True.
        auth_keystone (bool, optional): Enable Keystone authentication integration. Defaults to False.
        keystone_url (str, optional): URL for Keystone authentication service. Defaults to "".
        keystone_accepted_roles (list, optional): List of roles accepted by Keystone for access. Defaults to None.
        keystone_implicit_tenants (str, optional): Implicit tenant handling for Keystone (e.g., "swift"). Defaults to "swift".
        keystone_revocation_interval (int, optional): Token revocation check interval in seconds. Defaults to 1200.
        keystone_service_user_secret_name (str): Name of the secret containing Keystone service user credentials. Mandatory if auth_keystone is True.
        keystone_token_cache_size (int, optional): Size of token cache for Keystone authentication. Defaults to 1000.
        rgw_keystone_api_version (str, optional): Keystone API version for RGW authentication. Defaults to "3".
        rgw_keystone_implicit_tenants (str, optional): Enable implicit tenants for Keystone-Swift integration. Defaults to "true".
        rgw_s3_auth_use_keystone (str, optional): Use Keystone for S3 authentication. Defaults to "true".
        debug_rgw (str, optional): Debug level for RGW (e.g., "15" for detailed logging). Defaults to "0" (no debugging).

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'message' (str), and 'resource' (dict, if created/updated).
    """
    try:
        _load_k8s_config()
        custom_api = client.CustomObjectsApi()

        # Define the CephObjectStore resource for Rook
        object_store_body = {
            "apiVersion": "ceph.rook.io/v1",
            "kind": "CephObjectStore",
            "metadata": {
                "name": name,
                "namespace": namespace,
            },
            "spec": {
                "metadataPool": {
                    "failureDomain": "host",
                    "replicated": {"size": replicas},
                },
                "dataPool": {
                    "failureDomain": "host",
                    "replicated": {"size": replicas},
                },
                "preservePoolsOnDelete": preserve_pools_on_delete,
                "gateway": {
                    "port": port,
                    "instances": gateway_instances,
                    "ssl": ssl_enabled,
                    "type": "s3",  # Primary API type for S3 compatibility
                },
                "protocols": {
                    "s3": {"enabled": enable_s3_api},
                    "swift": {
                        "enabled": enable_swift_api,
                        "accountInUrl": swift_account_in_url,
                        "urlPrefix": swift_url_prefix,
                    },
                },
            },
        }

        # Add annotations if provided
        if annotations:
            object_store_body["metadata"]["annotations"] = annotations

        # Add gateway resources if provided
        if gateway_resources:
            object_store_body["spec"]["gateway"]["resources"] = gateway_resources

        # Configure Keystone authentication if enabled, under auth.keystone and gateway rgwConfig
        if auth_keystone:
            if not keystone_service_user_secret_name:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"keystone_service_user_secret_name is mandatory when auth_keystone is enabled for {name} in namespace {namespace}.",
                    "resource": {},
                }
            object_store_body["spec"]["auth"] = {
                "keystone": {
                    "url": keystone_url,
                    "acceptedRoles": keystone_accepted_roles
                    if keystone_accepted_roles
                    else ["admin", "member", "service"],
                    "implicitTenants": keystone_implicit_tenants,
                    "revocationInterval": keystone_revocation_interval,
                    "serviceUserSecretName": keystone_service_user_secret_name,
                    "tokenCacheSize": keystone_token_cache_size,
                }
            }
            object_store_body["spec"]["gateway"]["rgwConfig"] = {
                "rgw_keystone_api_version": rgw_keystone_api_version,
                "rgw_keystone_implicit_tenants": rgw_keystone_implicit_tenants,
                "rgw_s3_auth_use_keystone": rgw_s3_auth_use_keystone,
                "debug_rgw": debug_rgw if debug_rgw != "0" else "0",
            }

        # Check if CephObjectStore already exists
        try:
            existing_store = custom_api.get_namespaced_custom_object(
                group="ceph.rook.io",
                version="v1",
                namespace=namespace,
                plural="cephobjectstores",
                name=name,
            )
            # Compare existing spec with desired spec (simplified check)
            if existing_store.get("spec") == object_store_body.get("spec"):
                return {
                    "success": True,
                    "updated": False,
                    "message": f"CephObjectStore {name} already exists in namespace {namespace} with matching spec.",
                    "resource": existing_store,
                }
            else:
                # Delete the existing CephObjectStore before recreating due to update limitations
                try:
                    custom_api.delete_namespaced_custom_object(
                        group="ceph.rook.io",
                        version="v1",
                        namespace=namespace,
                        plural="cephobjectstores",
                        name=name,
                    )
                    return {
                        "success": True,
                        "updated": True,
                        "message": f"CephObjectStore {name} deleted in namespace {namespace}, will recreate with new spec.",
                        "resource": {},
                    }
                except ApiException as delete_err:
                    return {
                        "success": False,
                        "updated": False,
                        "message": f"Failed to delete existing CephObjectStore {name} in namespace {namespace}: {str(delete_err)[:100]}...",
                        "resource": {},
                    }
        except ApiException as e:
            if e.status == 404:
                # CephObjectStore does not exist, create it
                created_store = custom_api.create_namespaced_custom_object(
                    group="ceph.rook.io",
                    version="v1",
                    namespace=namespace,
                    plural="cephobjectstores",
                    body=object_store_body,
                )
                return {
                    "success": True,
                    "updated": True,
                    "message": f"CephObjectStore {name} created in namespace {namespace}.",
                    "resource": created_store,
                }
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to manage CephObjectStore {name} in namespace {namespace}: {str(e)}...",
                    "resource": {},
                }
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Error managing CephObjectStore {name} in namespace {namespace}: {str(e)[:100]}...",
            "resource": {},
        }
