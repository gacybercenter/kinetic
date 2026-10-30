# -*- coding: utf-8 -*-
"""
SaltStack execution module for Rook Ceph management.

This module provides functions to manage Rook Ceph Custom Resources directly,
rather than through Helm charts. It follows the pattern established in kinetic-k8s.py.
"""

import base64
import hashlib
import hmac
import json
import shlex
import socket
import ssl
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from urllib.parse import quote, urlparse

import salt.utils.decorators as decorators
from kubernetes import client, config
from kubernetes.client.rest import ApiException

import requests

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


def _spec_matches(desired, current):
    """True when every key we set is already present in the live spec.

    Rook adds defaults (healthCheck, zone, securePort, placement). A full
    equality check treats those as drift and used to delete the CR.
    """
    if isinstance(desired, dict):
        if not isinstance(current, dict):
            return False
        return all(
            _spec_matches(value, current.get(key))
            for key, value in desired.items()
        )
    if isinstance(desired, list):
        if not isinstance(current, list) or len(desired) != len(current):
            return False
        if all(isinstance(item, str) for item in desired + current):
            return sorted(desired) == sorted(current)
        return all(_spec_matches(a, b) for a, b in zip(desired, current))
    return desired == current


def _deep_merge(base, overlay):
    """Overlay keys onto a live spec without dropping Rook-injected fields."""
    if not isinstance(overlay, dict) or not isinstance(base, dict):
        return overlay
    merged = dict(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def _restart_rook_operator(namespace):
    """Roll the rook-ceph-operator Deployment so it re-reads the CR."""
    apps = client.AppsV1Api()
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    patch = {
        "spec": {
            "template": {
                "metadata": {
                    "annotations": {"kinetic.gcr/restarted-at": now}
                }
            }
        }
    }
    apps.patch_namespaced_deployment(
        name="rook-ceph-operator",
        namespace=namespace,
        body=patch,
    )


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
    encrypted_device=False,
    network_encryption=False,
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
        encrypted_device (bool): Encrypt new OSD devices (storage.config.encryptedDevice).
            Does not re-encrypt OSDs that already exist.
        network_encryption (bool): Enable msgr2 wire encryption
            (network.connections.encryption.enabled). Requires msgr2.
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
            if encrypted_device:
                if "config" not in spec["storage"]:
                    spec["storage"]["config"] = {}
                # Rook expects the string "true", not a boolean.
                spec["storage"]["config"]["encryptedDevice"] = "true"
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

            if network_encryption:
                spec["network"]["connections"] = {
                    "encryption": {"enabled": True},
                }
                spec["network"]["requireMsgr2"] = True

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
    enable_apis=None,
    rgw_config=None,
    rgw_command_flags=None,
    erasure_coded=None,
    enable_sts=False,
    sts_key=None,
    secure_port=None,
    ssl_certificate_ref=None,
    advertise_endpoint=None,
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
        enable_apis (list, optional): Explicit value for spec.protocols.enableAPIs, controlling
            which RGW frontends are actually mounted (e.g. ["s3", "swift", "swift_auth"],
            or ["admin"] for an Admin-Ops-only instance - see Rook's Object Multi-instance
            docs). If not given, defaults to ["s3"] and/or ["swift", "swift_auth"] based on
            enable_s3_api/enable_swift_api, since Rook's own default for this field does not
            reliably enable swift_auth alongside swift.
        rgw_config (dict, optional): Additional spec.gateway.rgwConfig entries (raw ceph.conf
            [client.rgw.*] key/value pairs, e.g. rgw_request_timeout, rgw_op_thread_timeout,
            rgw_thread_pool_size), merged on top of the Keystone-related rgwConfig keys built
            from the auth_keystone/rgw_keystone_*/debug_rgw args above (if auth_keystone is
            False, this is used as-is). Values here win on key collisions.
        rgw_command_flags (dict, optional): spec.gateway.rgwCommandFlags entries - extra
            command-line flags passed to the radosgw process itself (e.g.
            {"rgw-frontends": "beast port=80 request_timeout_ms=300000"}).
        erasure_coded (dict, optional): If set, dataPool uses erasure coding instead of
            replication. Keys: data_chunks, coding_chunks (or dataChunks/codingChunks).
        enable_sts (bool, optional): Enable RGW STS. Adds sts/iam to enableAPIs and sets
            rgw_s3_auth_use_sts. Requires sts_key (same value on every RGW in the zone).
        sts_key (str, optional): rgw_sts_key. At least 16 characters.
        secure_port (int, optional): spec.gateway.securePort. RGW listens TLS here
            when ssl_certificate_ref is set. Port 80 stays open for callers that
            cannot use the public name on the certificate.
        ssl_certificate_ref (str, optional): Secret in this namespace with
            tls.crt and tls.key. Rook mounts it as the beast TLS certificate.
        advertise_endpoint (dict, optional): spec.hosting.advertiseEndpoint.
            Keys dnsName, port, useTls. Rook's own RGW calls use this instead
            of the Service DNS name. Required when the TLS cert cannot list
            rook-ceph-rgw-<store>.<ns>.svc (a public ACME cert cannot).

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
                } if not erasure_coded else {
                    "failureDomain": "host",
                    "erasureCoded": {
                        "dataChunks": int(
                            erasure_coded.get("dataChunks", erasure_coded.get("data_chunks", 2))
                        ),
                        "codingChunks": int(
                            erasure_coded.get("codingChunks", erasure_coded.get("coding_chunks", 1))
                        ),
                    },
                },
                "preservePoolsOnDelete": preserve_pools_on_delete,
                "gateway": {
                    "port": port,
                    "instances": gateway_instances,
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

        # spec.protocols.enableAPIs controls which RGW frontends are actually
        # mounted, separate from the per-protocol "enabled" flags above -
        # without swift_auth explicitly listed here, Swift TempAuth-style
        # requests (and some Keystone-Swift flows) never reach the gateway.
        # Built before STS/Keystone so both can add rgwConfig keys.
        merged_rgw_config = {}

        if enable_apis is not None:
            object_store_body["spec"]["protocols"]["enableAPIs"] = enable_apis
        else:
            default_apis = []
            if enable_s3_api:
                default_apis.append("s3")
            if enable_swift_api:
                default_apis.extend(["swift", "swift_auth"])
            if enable_sts:
                for api in ("sts", "iam"):
                    if api not in default_apis:
                        default_apis.append(api)
            if default_apis:
                object_store_body["spec"]["protocols"]["enableAPIs"] = default_apis
        if enable_sts:
            apis = object_store_body["spec"]["protocols"].setdefault("enableAPIs", [])
            for api in ("s3", "sts", "iam"):
                if api not in apis:
                    apis.append(api)
            if not sts_key or len(str(sts_key)) < 16:
                return {
                    "success": False,
                    "updated": False,
                    "message": (
                        f"sts_key of at least 16 characters is required when "
                        f"enable_sts is set for {name}"
                    ),
                    "resource": {},
                }
            merged_rgw_config["rgw_s3_auth_use_sts"] = "true"
            merged_rgw_config["rgw_sts_key"] = str(sts_key)

        # Add annotations if provided
        if annotations:
            object_store_body["metadata"]["annotations"] = annotations

        # Add gateway resources if provided
        if gateway_resources:
            object_store_body["spec"]["gateway"]["resources"] = gateway_resources
        if secure_port:
            object_store_body["spec"]["gateway"]["securePort"] = int(secure_port)
        if ssl_certificate_ref:
            object_store_body["spec"]["gateway"]["sslCertificateRef"] = ssl_certificate_ref
        if advertise_endpoint:
            object_store_body["spec"]["hosting"] = {
                "advertiseEndpoint": {
                    "dnsName": advertise_endpoint["dnsName"],
                    "port": int(advertise_endpoint.get("port", secure_port or 443)),
                    "useTls": bool(advertise_endpoint.get("useTls", True)),
                },
            }

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
            merged_rgw_config.update({
                "rgw_keystone_api_version": rgw_keystone_api_version,
                "rgw_keystone_implicit_tenants": rgw_keystone_implicit_tenants,
                "rgw_s3_auth_use_keystone": rgw_s3_auth_use_keystone,
                "debug_rgw": debug_rgw if debug_rgw != "0" else "0",
            })

        # rgw_config lets callers pass arbitrary extra ceph.conf [client.rgw.*]
        # key/value pairs (e.g. rgw_request_timeout, rgw_thread_pool_size)
        # without this function needing a named arg for every possible option.
        # It merges on top of (and can override) the Keystone-derived keys above.
        if rgw_config:
            merged_rgw_config.update(rgw_config)
        if merged_rgw_config:
            object_store_body["spec"]["gateway"]["rgwConfig"] = merged_rgw_config

        if rgw_command_flags:
            object_store_body["spec"]["gateway"]["rgwCommandFlags"] = rgw_command_flags

        # Check if CephObjectStore already exists
        try:
            existing_store = custom_api.get_namespaced_custom_object(
                group="ceph.rook.io",
                version="v1",
                namespace=namespace,
                plural="cephobjectstores",
                name=name,
            )
            desired = object_store_body.get("spec")
            if _spec_matches(desired, existing_store.get("spec") or {}):
                return {
                    "success": True,
                    "updated": False,
                    "message": f"CephObjectStore {name} already exists in namespace {namespace} with matching spec.",
                    "resource": existing_store,
                }
            try:
                # Replace with a merged spec. kubernetes 29-31 rejects
                # _content_type on patch. Do not delete the CR.
                metadata = existing_store.get("metadata") or {}
                body = {
                    "apiVersion": "ceph.rook.io/v1",
                    "kind": "CephObjectStore",
                    "metadata": {
                        "name": name,
                        "namespace": namespace,
                        "resourceVersion": metadata.get("resourceVersion"),
                    },
                    "spec": _deep_merge(existing_store.get("spec") or {}, desired),
                }
                patched = custom_api.replace_namespaced_custom_object(
                    group="ceph.rook.io",
                    version="v1",
                    namespace=namespace,
                    plural="cephobjectstores",
                    name=name,
                    body=body,
                )
                restart_note = ""
                try:
                    _restart_rook_operator(namespace)
                    restart_note = "; restarted deployment/rook-ceph-operator"
                except ApiException as restart_err:
                    restart_note = (
                        f"; failed to restart rook-ceph-operator: "
                        f"{str(restart_err)[:80]}"
                    )
                return {
                    "success": True,
                    "updated": True,
                    "message": (
                        f"CephObjectStore {name} updated in namespace {namespace}"
                        f"{restart_note}."
                    ),
                    "resource": patched,
                }
            except ApiException as patch_err:
                return {
                    "success": False,
                    "updated": False,
                    "message": (
                        f"Failed to update CephObjectStore {name} in namespace "
                        f"{namespace}: {str(patch_err)[:150]}"
                    ),
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


def _toolbox_radosgw(namespace, args, timeout=120):
    """Run radosgw-admin in the rook-ceph-tools pod.

    Returns {success, rc, stdout, stderr}. The client secret is an argv
    value and is not echoed back.
    """
    from kubernetes.stream import stream

    core = client.CoreV1Api()
    pods = core.list_namespaced_pod(
        namespace=namespace,
        label_selector="app=rook-ceph-tools",
    )
    running = [
        p.metadata.name
        for p in pods.items
        if p.status and p.status.phase == "Running"
    ]
    if not running:
        return {
            "success": False,
            "rc": 1,
            "stdout": "",
            "stderr": f"no running rook-ceph-tools pod in {namespace}",
        }
    command = ["/bin/sh", "-c", "radosgw-admin " + " ".join(shlex.quote(a) for a in args) + "; echo __RC:$?"]
    stdout = stream(
        core.connect_get_namespaced_pod_exec,
        running[0],
        namespace,
        command=command,
        container="rook-ceph-tools",
        stderr=True,
        stdin=False,
        stdout=True,
        tty=False,
        _request_timeout=timeout,
    )
    rc = 1
    lines = (stdout or "").splitlines()
    if lines and lines[-1].startswith("__RC:"):
        rc = int(lines[-1].split(":", 1)[1] or 1)
        lines = lines[:-1]
    text = "\n".join(lines)
    return {"success": rc == 0, "rc": rc, "stdout": text, "stderr": "" if rc == 0 else text}


def _json_equal(left, right):
    try:
        return json.loads(left) == json.loads(right)
    except (TypeError, ValueError):
        return str(left).strip() == str(right).strip()


def _tenant_args(tenant):
    """RGW role commands reject or mis-scope ``--tenant`` when it is empty.

    Role create/get/policy must omit the flag unless a tenant is actually set.
    """
    if tenant:
        return ["--tenant", tenant]
    return []


def _aws_uri_encode(value, safe="-_.~"):
    """AWS SigV4 percent-encoding (spaces are ``%20``, not ``+``)."""
    return quote(str(value), safe=safe)


def _canonical_query(params):
    pairs = []
    for key, value in params.items():
        pairs.append((_aws_uri_encode(key), _aws_uri_encode(value)))
    pairs.sort()
    return "&".join(f"{key}={value}" for key, value in pairs)


def _aws4_signing_key(secret_key, datestamp, region, service):
    key = ("AWS4" + secret_key).encode("utf-8")
    for part in (datestamp, region, service, "aws4_request"):
        key = hmac.new(key, part.encode("utf-8"), hashlib.sha256).digest()
    return key


def _iam_sign_headers(method, url, query, access_key, secret_key, region, service, payload=b""):
    """Header-based AWS SigV4. No extra dependency.

    ``query`` is the canonical query string. Tentacle reads IAM ``Action``
    from the POST body, so callers sign an empty query and pass the form
    body as ``payload``. The payload hash in the canonical request is what
    RGW recomputes from that body (``PayloadHash``).
    """
    parsed = urlparse(url)
    host = parsed.hostname or ""
    if parsed.port and not (
        (parsed.scheme == "https" and parsed.port == 443)
        or (parsed.scheme == "http" and parsed.port == 80)
    ):
        host = f"{host}:{parsed.port}"
    now = datetime.now(timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    datestamp = amz_date[:8]
    payload_hash = hashlib.sha256(payload).hexdigest()
    path = _aws_uri_encode(parsed.path or "/", safe="/")
    canonical_headers = (
        f"host:{host}\n"
        f"x-amz-content-sha256:{payload_hash}\n"
        f"x-amz-date:{amz_date}\n"
    )
    signed_headers = "host;x-amz-content-sha256;x-amz-date"
    canonical_request = "\n".join([
        method,
        path,
        query,
        canonical_headers,
        signed_headers,
        payload_hash,
    ])
    scope = f"{datestamp}/{region}/{service}/aws4_request"
    string_to_sign = "\n".join([
        "AWS4-HMAC-SHA256",
        amz_date,
        scope,
        hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
    ])
    signature = hmac.new(
        _aws4_signing_key(secret_key, datestamp, region, service),
        string_to_sign.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    authorization = (
        f"AWS4-HMAC-SHA256 Credential={access_key}/{scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )
    return {
        "Host": host,
        "X-Amz-Date": amz_date,
        "X-Amz-Content-Sha256": payload_hash,
        "Authorization": authorization,
    }, path


def _iam_endpoint(endpoint):
    """Normalize an RGW base URL to ``(scheme, host, path)``.

    Default ports are omitted so the signed Host header matches the URL
    ``requests`` will send.
    """
    raw = endpoint.strip()
    if "://" not in raw:
        raw = "http://" + raw
    parsed = urlparse(raw)
    host = parsed.hostname or ""
    if parsed.port and not (
        (parsed.scheme == "https" and parsed.port == 443)
        or (parsed.scheme == "http" and parsed.port == 80)
    ):
        host = f"{host}:{parsed.port}"
    path = parsed.path or "/"
    if not path.endswith("/"):
        path += "/"
    return parsed.scheme or "http", host, path


def _host_resolves(host):
    """False when this process cannot resolve host (a minion has no cluster DNS)."""
    hostname = (host or "").split(":", 1)[0]
    if not hostname:
        return False
    try:
        socket.getaddrinfo(hostname, None)
    except socket.gaierror:
        return False
    return True


def _toolbox_http(namespace, method, url, headers, body=b"", timeout=30, insecure=False):
    """HTTP from the rook-ceph-tools pod. Returns ``(status, body)``.

    Used when the signed URL is a cluster service name. The minion that runs
    Salt cannot resolve ``*.svc``; the toolbox pod can. ``Host`` is omitted so
    curl derives it from the URL, which is the host the signature was built for.
    """
    from kubernetes.stream import stream

    _load_k8s_config()
    core = client.CoreV1Api()
    pods = core.list_namespaced_pod(
        namespace=namespace,
        label_selector="app=rook-ceph-tools",
    )
    running = [
        p.metadata.name
        for p in pods.items
        if p.status and p.status.phase == "Running"
    ]
    if not running:
        return 0, f"no running rook-ceph-tools pod in {namespace}"
    argv = ["curl", "-sS", "-m", str(int(timeout)), "-X", method, "-w", "\n__HTTP:%{http_code}"]
    if insecure:
        argv.append("-k")
    for key, value in headers.items():
        if key.lower() == "host":
            continue
        argv.extend(["-H", f"{key}: {value}"])
    if body:
        argv.extend(["--data-binary", body.decode("utf-8")])
    argv.append(url)
    command = ["/bin/sh", "-c", " ".join(shlex.quote(part) for part in argv)]
    stdout = stream(
        core.connect_get_namespaced_pod_exec,
        running[0],
        namespace,
        command=command,
        container="rook-ceph-tools",
        stderr=False,
        stdin=False,
        stdout=True,
        tty=False,
        _request_timeout=timeout + 15,
    )
    text = stdout or ""
    if "__HTTP:" not in text:
        return 0, text.replace("\n", " ")[:300] or "curl produced no status"
    body, _, code = text.rpartition("__HTTP:")
    try:
        status = int(code.strip() or 0)
    except ValueError:
        status = 0
    return status, body.rstrip("\n")


def _iam_result(status, text):
    if status == 404:
        return False, 404, text
    if status >= 400 or status == 0:
        return False, status, (text or "").replace("\n", " ")[:300]
    return True, status, text


def _iam_request(
    endpoint,
    action,
    access_key,
    secret_key,
    params=None,
    region="us-east-1",
    service="iam",
    verify=True,
    timeout=30,
    namespace=None,
):
    """POST an RGW IAM query-API action. Returns ``(ok, status, body)``.

    ``body`` is the raw XML. ``format=json`` collapses repeated ``member``
    tags, so callers parse XML instead. ``ok`` is false for HTTP errors
    other than 404 (missing entity).

    A ``*.svc`` URL is signed here and fetched from the toolbox pod when this
    process cannot resolve it.
    """
    # Tentacle (this cluster) dispatches IAM only when Action is in the
    # POST body. A query-string Action is op=unknown and returns 405.
    form = {
        "Action": action,
        "Version": "2010-05-08",
    }
    form.update(params or {})
    body = _canonical_query(form).encode("utf-8")
    scheme, host, path = _iam_endpoint(endpoint)
    url = f"{scheme}://{host}{path}"
    headers, signed_path = _iam_sign_headers(
        "POST", url, "", access_key, secret_key, region, service, payload=body,
    )
    headers["Content-Type"] = "application/x-www-form-urlencoded"
    signed_url = f"{scheme}://{host}{signed_path}"
    if namespace and not _host_resolves(host):
        status, text = _toolbox_http(
            namespace, "POST", signed_url, headers, body=body,
            timeout=timeout, insecure=not verify,
        )
        return _iam_result(status, text)
    try:
        resp = requests.post(signed_url, headers=headers, data=body, verify=verify, timeout=timeout)
    except requests.RequestException as exc:
        if not namespace:
            return False, 0, str(exc)[:300]
        status, text = _toolbox_http(
            namespace, "POST", signed_url, headers, body=body,
            timeout=timeout, insecure=not verify,
        )
        if status == 0:
            return False, 0, f"{exc.__class__.__name__}: {text}"
        return _iam_result(status, text)
    return _iam_result(resp.status_code, resp.text or "")


def _iam_local(tag):
    return (tag or "").rsplit("}", 1)[-1]


def _iam_xml(text):
    try:
        return ET.fromstring(text)
    except ET.ParseError:
        return None


def _iam_error_code(text):
    root = _iam_xml(text) if isinstance(text, str) else None
    if root is None:
        return ""
    for node in root.iter():
        if _iam_local(node.tag) == "Code" and node.text:
            return node.text.strip()
    return ""


def _iam_members(text, section):
    """Texts of ``<member>`` children under ``section``. None if unparseable."""
    root = _iam_xml(text) if isinstance(text, str) else None
    if root is None:
        return None
    members = []
    for node in root.iter():
        if _iam_local(node.tag) != section:
            continue
        for child in list(node):
            if _iam_local(child.tag) == "member" and (child.text or "").strip():
                members.append(child.text.strip())
    return members


def _iam_missing(status, body):
    text = body if isinstance(body, str) else ""
    code = _iam_error_code(text)
    return status == 404 or code.startswith("NoSuch") or "NoSuchEntity" in text


def _oidc_provider_id(issuer_url):
    """Issuer URL as RGW stores it: scheme stripped, no trailing slash.

    Matches ``WebTokenEngine::get_provider``: the JWT ``iss`` has ``http://``
    or ``https://`` removed, then becomes
    ``arn:aws:iam::<tenant>:oidc-provider/<that>``.
    """
    parsed = urlparse(issuer_url.strip())
    host = parsed.netloc
    if host.startswith("www."):
        host = host[4:]
    path = (parsed.path or "").rstrip("/")
    return host + path


def _oidc_provider_arn(issuer_url, tenant=""):
    return f"arn:aws:iam::{tenant}:oidc-provider/{_oidc_provider_id(issuer_url)}"


def _sha1_thumbprint(der_bytes):
    return hashlib.sha1(der_bytes).hexdigest()


def _tls_peer_thumbprint(issuer_url, verify=True, timeout=10):
    """SHA1 of the issuer TLS leaf, in case JWKS has no ``x5c``."""
    parsed = urlparse(issuer_url)
    if parsed.scheme != "https" or not parsed.hostname:
        return None
    port = parsed.port or 443
    context = ssl.create_default_context()
    if not verify:
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
    try:
        with socket.create_connection((parsed.hostname, port), timeout=timeout) as raw:
            with context.wrap_socket(raw, server_hostname=parsed.hostname) as wrapped:
                der = wrapped.getpeercert(binary_form=True)
    except (OSError, ssl.SSLError):
        return None
    if not der:
        return None
    return _sha1_thumbprint(der)


def _jwks_thumbprints(issuer_url, verify=True, timeout=15):
    """SHA1 of every ``x5c`` cert on the issuer JWKS.

    That is what RGW compares during ``AssumeRoleWithWebIdentity``, not the
    TLS server cert. Keycloak omits ``x5c`` unless a certificate is set on
    the realm keys; discovery then returns nothing and a thumbprint must be
    passed in.
    """
    issuer = issuer_url.rstrip("/")
    try:
        config_resp = requests.get(
            issuer + "/.well-known/openid-configuration",
            verify=verify,
            timeout=timeout,
        )
        config_resp.raise_for_status()
        jwks_uri = config_resp.json().get("jwks_uri")
        if not jwks_uri:
            return []
        jwks_resp = requests.get(jwks_uri, verify=verify, timeout=timeout)
        jwks_resp.raise_for_status()
        keys = jwks_resp.json().get("keys") or []
    except (requests.RequestException, ValueError, TypeError):
        return []
    thumbprints = []
    for key in keys:
        for cert_b64 in key.get("x5c") or []:
            try:
                der = base64.b64decode(cert_b64)
            except (TypeError, ValueError):
                continue
            if der:
                thumbprints.append(_sha1_thumbprint(der))
    return thumbprints


def _discover_thumbprints(issuer_url, verify=True):
    """Prefer JWKS ``x5c``; fall back to the issuer TLS leaf. Cap at 5."""
    found = []
    for thumbprint in _jwks_thumbprints(issuer_url, verify=verify):
        if thumbprint not in found:
            found.append(thumbprint)
    peer = _tls_peer_thumbprint(issuer_url, verify=verify)
    if peer and peer not in found:
        found.append(peer)
    return found[:5]


def _rgw_target_args(realm=None, zonegroup=None, zone=None):
    """Pin radosgw-admin at a realm. The toolbox defaults to zone "default".

    A Rook ``CephObjectStore`` runs RGW with ``--rgw-realm/--rgw-zone`` set to
    the store name. Users and roles created without these flags land in the
    default zone, which that RGW never reads.
    """
    args = []
    if realm:
        args.extend(["--rgw-realm", realm])
    if zonegroup:
        args.extend(["--rgw-zonegroup", zonegroup])
    if zone:
        args.extend(["--rgw-zone", zone])
    return args


def _first_rgw_key(payload):
    for key in payload.get("keys") or []:
        if key.get("access_key") and key.get("secret_key"):
            return key["access_key"], key["secret_key"]
    return None, None


def _has_oidc_cap(payload):
    for cap in payload.get("caps") or []:
        if cap.get("type") == "oidc-provider" and "*" in str(cap.get("perm", "")):
            return True
    return False


def _ensure_iam_admin(namespace, uid, realm=None, zonegroup=None, zone=None):
    """Ensure an RGW user with ``oidc-provider=*`` exists in this realm.

    Created with ``radosgw-admin`` in the toolbox, not ``CephObjectStoreUser``.
    Rook's object-user controller calls the Admin Ops API and fails here with
    ``NoSuchBucket`` before it ever writes the Kubernetes secret.
    The secret key is returned to the caller and is not included in messages.
    """
    target = _rgw_target_args(realm, zonegroup, zone)
    info = _toolbox_radosgw(namespace, ["user", "info", "--uid", uid, *target])
    if info["success"]:
        try:
            payload = json.loads(info["stdout"])
        except ValueError:
            return {"success": False, "message": f"user info for {uid} was not JSON"}
    else:
        created = _toolbox_radosgw(
            namespace,
            ["user", "create", "--uid", uid, "--display-name", uid, *target],
        )
        if not created["success"]:
            return {
                "success": False,
                "message": f"failed to create IAM admin {uid}: {created['stderr'][:200]}",
            }
        try:
            payload = json.loads(created["stdout"])
        except ValueError:
            return {"success": False, "message": f"IAM admin {uid} created but output was not JSON"}
    if not _has_oidc_cap(payload):
        capped = _toolbox_radosgw(
            namespace,
            ["caps", "add", "--uid", uid, "--caps", "oidc-provider=*", *target],
        )
        if not capped["success"]:
            return {
                "success": False,
                "message": f"failed to add oidc-provider caps to {uid}: {capped['stderr'][:200]}",
            }
    access_key, secret_key = _first_rgw_key(payload)
    if not access_key:
        keyed = _toolbox_radosgw(
            namespace, ["key", "create", "--uid", uid, "--gen-secret", *target],
        )
        if not keyed["success"]:
            return {
                "success": False,
                "message": f"failed to create a key for {uid}: {keyed['stderr'][:200]}",
            }
        try:
            access_key, secret_key = _first_rgw_key(json.loads(keyed["stdout"]))
        except ValueError:
            access_key, secret_key = None, None
    if not access_key or not secret_key:
        return {"success": False, "message": f"IAM admin {uid} has no keys"}
    return {"success": True, "access_key": access_key, "secret_key": secret_key}


def _rgw_user_keys(namespace, secret_name, timeout=60):
    """Read Rook's object-user Secret, waiting briefly for the operator."""
    _load_k8s_config()
    core = client.CoreV1Api()
    deadline = time.monotonic() + timeout
    last_error = f"secret {secret_name} not found in {namespace}"
    while True:
        try:
            secret = core.read_namespaced_secret(secret_name, namespace)
            data = secret.data or {}
            access = base64.b64decode(data["AccessKey"]).decode("utf-8") if data.get("AccessKey") else ""
            secret_key = base64.b64decode(data["SecretKey"]).decode("utf-8") if data.get("SecretKey") else ""
            if access and secret_key:
                return {"success": True, "access_key": access, "secret_key": secret_key}
            last_error = f"secret {secret_name} has no AccessKey/SecretKey yet"
        except ApiException as exc:
            last_error = str(exc)[:200]
            if exc.status != 404:
                break
        except Exception as exc:
            last_error = str(exc)[:200]
            break
        if time.monotonic() >= deadline:
            break
        time.sleep(2)
    return {"success": False, "message": last_error}


def oidc_provider_present(
    namespace,
    name,
    issuer_url,
    client_id,
    client_secret=None,
    tenant="",
    thumbprints=None,
    endpoint=None,
    access_key=None,
    secret_key=None,
    store=None,
    iam_user="rgw-iam-admin",
    realm=None,
    zonegroup=None,
    zone=None,
    region="us-east-1",
    service="iam",
    verify=True,
    discover_thumbprints=True,
):
    """Ensure an RGW OIDC provider via the IAM query API.

    ``radosgw-admin oidc provider`` is newer than the releases this cluster
    runs. ``CreateOpenIDConnectProvider`` has been the documented API since
    well before that CLI existed
    (https://docs.ceph.com/en/reef/radosgw/oidc/).

    The provider is keyed by issuer URL, not ``name``. RGW strips the scheme
    and stores ``arn:aws:iam::<tenant>:oidc-provider/<host/path>``. There is
    no client secret on this API; ``client_secret`` is accepted and ignored
    so older state calls keep working.

    Credentials are an RGW user with ``oidc-provider=*`` caps in the
    store's realm. Pass ``access_key``/``secret_key``, or ``store`` (realm,
    zonegroup, and zone default to the store name) and this creates
    ``iam_user`` with ``radosgw-admin`` in the toolbox. Do not use a
    ``CephObjectStoreUser`` for this: Rook's controller calls the Admin Ops
    API and fails with ``NoSuchBucket`` on this store, so the secret is
    never written. A user of the same name in the default zone is a
    different user and will not authenticate to this RGW.

    Thumbprints are SHA1 of the IdP certificates (JWKS ``x5c``, which is what
    STS checks). They are discovered from the issuer when omitted. Ceph
    rejects a create with an empty thumbprint list.
    """
    try:
        # STS looks the provider up from the token iss with the scheme stripped
        # and no trailing slash. Keycloak's iss has none; a trailing slash here
        # would store a provider STS can never find.
        issuer_url = (issuer_url or "").strip().rstrip("/")
        if not issuer_url.startswith(("http://", "https://")):
            return {
                "success": False,
                "updated": False,
                "message": f"issuer_url for OIDC provider {name} must be an http(s) URL",
            }
        if isinstance(client_id, str):
            client_ids = [client_id] if client_id else []
        else:
            client_ids = [str(item) for item in (client_id or []) if item]
        wanted_prints = []
        for item in thumbprints or []:
            cleaned = str(item).strip().lower().replace(":", "")
            if cleaned and cleaned not in wanted_prints:
                wanted_prints.append(cleaned)
        if not wanted_prints and discover_thumbprints:
            wanted_prints = _discover_thumbprints(issuer_url, verify=verify)
        if not wanted_prints:
            return {
                "success": False,
                "updated": False,
                "message": (
                    f"no thumbprints for OIDC provider {name}; pass thumbprints "
                    "or expose x5c on the issuer JWKS"
                ),
            }
        if len(wanted_prints) > 5:
            return {
                "success": False,
                "updated": False,
                "message": "RGW allows at most 5 OIDC provider thumbprints",
            }

        if not access_key or not secret_key:
            if not store and not realm:
                return {
                    "success": False,
                    "updated": False,
                    "message": (
                        "access_key and secret_key are required, or set store "
                        "so the IAM admin can be created in that realm"
                    ),
                }
            _load_k8s_config()
            keys = _ensure_iam_admin(
                namespace,
                iam_user,
                realm=realm or store,
                zonegroup=zonegroup or store,
                zone=zone or store,
            )
            if not keys["success"]:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"IAM admin keys unavailable: {keys['message']}",
                }
            access_key = keys["access_key"]
            secret_key = keys["secret_key"]
        if not endpoint:
            if not store:
                return {
                    "success": False,
                    "updated": False,
                    "message": "endpoint or store is required to reach RGW",
                }
            endpoint = f"http://rook-ceph-rgw-{store}.{namespace}.svc"

        provider_arn = _oidc_provider_arn(issuer_url, tenant)

        def call(action, params=None):
            return _iam_request(
                endpoint,
                action,
                access_key,
                secret_key,
                params=params,
                region=region,
                service=service,
                verify=verify,
                namespace=namespace,
            )

        ok, status, body = call("GetOpenIDConnectProvider", {"OpenIDConnectProviderArn": provider_arn})
        exists = ok
        if not ok:
            if _iam_missing(status, body):
                exists = False
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"failed to get OIDC provider {name}: HTTP {status} {body}",
                }

        changes = []
        if not exists:
            params = {"Url": issuer_url}
            for index, thumbprint in enumerate(wanted_prints, start=1):
                params[f"ThumbprintList.member.{index}"] = thumbprint
            for index, cid in enumerate(client_ids, start=1):
                params[f"ClientIDList.member.{index}"] = cid
            created_ok, created_status, created_body = call("CreateOpenIDConnectProvider", params)
            already = (
                created_status == 409
                or _iam_error_code(created_body) == "EntityAlreadyExists"
                or (isinstance(created_body, str) and "already in use" in created_body)
            )
            if not created_ok and not already:
                return {
                    "success": False,
                    "updated": False,
                    "message": (
                        f"failed to create OIDC provider {name}: "
                        f"HTTP {created_status} {created_body}"
                    ),
                }
            if created_ok:
                return {
                    "success": True,
                    "updated": True,
                    "message": f"OIDC provider {name} created ({provider_arn})",
                    "arn": provider_arn,
                    "thumbprints": wanted_prints,
                }
            ok, status, body = call(
                "GetOpenIDConnectProvider", {"OpenIDConnectProviderArn": provider_arn},
            )
            if not ok:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"OIDC provider {name} exists but could not be read",
                }

        current_ids = _iam_members(body, "ClientIDList")
        current_prints = _iam_members(body, "ThumbprintList")
        if current_ids is None or current_prints is None:
            return {
                "success": False,
                "updated": False,
                "message": f"OIDC provider {name} response was not XML",
            }
        current_prints = [item.lower() for item in current_prints]
        for cid in client_ids:
            if cid not in current_ids:
                added_ok, added_status, added_body = call(
                    "AddClientIDToOpenIDConnectProvider",
                    {"OpenIDConnectProviderArn": provider_arn, "ClientID": cid},
                )
                if not added_ok:
                    return {
                        "success": False,
                        "updated": bool(changes),
                        "message": f"failed to add client id to {name}: HTTP {added_status} {added_body}",
                    }
                changes.append(f"client_id {cid}")
        for cid in current_ids:
            if cid not in client_ids:
                removed_ok, removed_status, removed_body = call(
                    "RemoveClientIDFromOpenIDConnectProvider",
                    {"OpenIDConnectProviderArn": provider_arn, "ClientID": cid},
                )
                if not removed_ok:
                    return {
                        "success": False,
                        "updated": bool(changes),
                        "message": (
                            f"failed to remove client id from {name}: "
                            f"HTTP {removed_status} {removed_body}"
                        ),
                    }
                changes.append(f"removed client_id {cid}")
        if sorted(current_prints) != sorted(wanted_prints):
            params = {"OpenIDConnectProviderArn": provider_arn}
            for index, thumbprint in enumerate(wanted_prints, start=1):
                params[f"ThumbprintList.member.{index}"] = thumbprint
            updated_ok, updated_status, updated_body = call(
                "UpdateOpenIDConnectProviderThumbprint", params,
            )
            if not updated_ok:
                return {
                    "success": False,
                    "updated": bool(changes),
                    "message": (
                        f"failed to update thumbprints for {name}: "
                        f"HTTP {updated_status} {updated_body}"
                    ),
                }
            changes.append("thumbprints")
        return {
            "success": True,
            "updated": bool(changes),
            "message": (
                f"OIDC provider {name} updated ({', '.join(changes)})"
                if changes
                else f"OIDC provider {name} already matches"
            ),
            "arn": provider_arn,
            "thumbprints": wanted_prints,
        }
    except Exception as exc:
        return {"success": False, "updated": False, "message": str(exc)[:200]}


def rgw_role_present(
    namespace,
    role_name,
    provider_name,
    audience,
    tenant="",
    path="/",
    audience_claim="app_id",
    issuer_url=None,
    groups=None,
    groups_claim="groups",
    group_prefix="",
    realm=None,
    zonegroup=None,
    zone=None,
):
    """Ensure an RGW IAM role that trusts an OIDC provider.

    Pass ``issuer_url`` when the provider was created via the IAM API. STS
    looks the provider up from the token ``iss`` (scheme stripped), so the
    trust policy principal and condition must use that string, not the
    friendly provider name. ``provider_name`` is the fallback for a provider
    created by name with a newer ``radosgw-admin oidc provider`` CLI.

    ``groups`` is checked only at AssumeRoleWithWebIdentity. RGW does not
    keep the JWT on later S3 calls, so a group cannot be a bucket-policy
    condition. One role per group, with that group's buckets on the inline
    policy. Match the claim exactly. Keycloak is configured to emit the bare
    LDAP group name (``ss3-admins``, not ``/ss3-admins``), so ``group_prefix``
    defaults to empty. Pass ``group_prefix="/"`` only for a mapper that still
    emits the full path. Multiple groups are OR.
    """
    try:
        _load_k8s_config()
        provider_id = _oidc_provider_id(issuer_url) if issuer_url else provider_name
        conditions = {f"{provider_id}:{audience_claim}": audience}
        if groups:
            wanted = groups if isinstance(groups, list) else [groups]
            if group_prefix:
                wanted = [
                    item if str(item).startswith(group_prefix) else f"{group_prefix}{item}"
                    for item in wanted
                ]
            conditions[f"{provider_id}:{groups_claim}"] = wanted
        policy = {
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {
                    "Federated": [f"arn:aws:iam::{tenant}:oidc-provider/{provider_id}"],
                },
                "Action": "sts:AssumeRoleWithWebIdentity",
                "Condition": {"StringEquals": conditions},
            }],
        }
        doc = json.dumps(policy)
        target = _rgw_target_args(realm, zonegroup, zone)
        info = _toolbox_radosgw(
            namespace,
            ["role", "get", "--role-name", role_name, *_tenant_args(tenant), *target],
        )
        if info["success"]:
            try:
                payload = json.loads(info["stdout"])
                current_doc = payload.get(
                    "assume_role_policy_document",
                    payload.get("AssumeRolePolicyDocument", "{}"),
                )
            except ValueError:
                current_doc = "{}"
            if _json_equal(current_doc, doc):
                return {
                    "success": True,
                    "updated": False,
                    "message": f"RGW role {role_name} already matches",
                }
            modified = _toolbox_radosgw(
                namespace,
                [
                    "role-trust-policy", "modify",
                    "--role-name", role_name,
                    *_tenant_args(tenant),
                    "--assume-role-policy-doc", doc,
                    *target,
                ],
            )
            return {
                "success": modified["success"],
                "updated": modified["success"],
                "message": (
                    f"RGW role {role_name} trust policy updated"
                    if modified["success"]
                    else f"failed to update trust policy for {role_name}: {modified['stderr'][:200]}"
                ),
            }
        created = _toolbox_radosgw(
            namespace,
            [
                "role", "create",
                "--role-name", role_name,
                "--path", path,
                *_tenant_args(tenant),
                "--assume-role-policy-doc", doc,
                *target,
            ],
        )
        return {
            "success": created["success"],
            "updated": created["success"],
            "message": (
                f"RGW role {role_name} created"
                if created["success"]
                else f"failed to create RGW role {role_name}: {created['stderr'][:200]}"
            ),
        }
    except Exception as exc:
        return {"success": False, "updated": False, "message": str(exc)[:200]}


def _s3_request(
    endpoint,
    method,
    bucket,
    access_key,
    secret_key,
    namespace=None,
    region="us-east-1",
    verify=True,
    timeout=30,
):
    """Signed path-style S3 call. Returns ``(ok, status, body)``.

    ``radosgw-admin bucket create`` is gone on this Ceph. CreateBucket is a
    PUT of ``/<bucket>`` with an empty body. A ``*.svc`` host that this
    process cannot resolve is fetched from the toolbox pod.
    """
    scheme, host, path = _iam_endpoint(endpoint)
    object_path = path.rstrip("/") + "/" + bucket
    url = f"{scheme}://{host}{object_path}"
    headers, signed_path = _iam_sign_headers(
        method, url, "", access_key, secret_key, region, "s3", payload=b"",
    )
    signed_url = f"{scheme}://{host}{signed_path}"
    if namespace and not _host_resolves(host):
        return _iam_result(*_toolbox_http(
            namespace, method, signed_url, headers, timeout=timeout, insecure=not verify,
        ))
    try:
        resp = requests.request(
            method, signed_url, headers=headers, data=b"", verify=verify, timeout=timeout,
        )
    except requests.RequestException as exc:
        if not namespace:
            return False, 0, str(exc)[:300]
        status, text = _toolbox_http(
            namespace, method, signed_url, headers, timeout=timeout, insecure=not verify,
        )
        if status == 0:
            return False, 0, f"{exc.__class__.__name__}: {text}"
        return _iam_result(status, text)
    return _iam_result(resp.status_code, resp.text or "")


def rgw_bucket_present(
    namespace,
    name,
    owner,
    realm=None,
    zonegroup=None,
    zone=None,
    endpoint=None,
    store=None,
    region="us-east-1",
    verify=True,
):
    """Ensure an S3 bucket exists in the store's realm.

    ``name`` of ``*`` is skipped. The owner is an RGW user created in the
    realm if missing. That user's keys sign CreateBucket and are not returned.
    A bucket that already exists, including one owned by someone else, is left
    alone.
    """
    if name == "*":
        return {"success": True, "updated": False, "message": "wildcard is not a bucket"}
    try:
        if not endpoint:
            if not store:
                return {
                    "success": False,
                    "updated": False,
                    "message": "endpoint or store is required to create a bucket",
                }
            endpoint = f"http://rook-ceph-rgw-{store}.{namespace}.svc"
        _load_k8s_config()
        target = _rgw_target_args(realm, zonegroup, zone)
        info = _toolbox_radosgw(namespace, ["user", "info", "--uid", owner, *target])
        if info["success"]:
            try:
                payload = json.loads(info["stdout"])
            except ValueError:
                return {"success": False, "updated": False, "message": f"user info for {owner} was not JSON"}
        else:
            created = _toolbox_radosgw(
                namespace,
                ["user", "create", "--uid", owner, "--display-name", owner, *target],
            )
            if not created["success"]:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"failed to create bucket owner {owner}: {created['stderr'][:200]}",
                }
            try:
                payload = json.loads(created["stdout"])
            except ValueError:
                return {"success": False, "updated": False, "message": f"owner {owner} created but output was not JSON"}
        access_key, secret_key = _first_rgw_key(payload)
        if not access_key:
            keyed = _toolbox_radosgw(
                namespace, ["key", "create", "--uid", owner, "--gen-secret", *target],
            )
            if not keyed["success"]:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"failed to create a key for {owner}: {keyed['stderr'][:200]}",
                }
            try:
                access_key, secret_key = _first_rgw_key(json.loads(keyed["stdout"]))
            except ValueError:
                access_key, secret_key = None, None
        if not access_key or not secret_key:
            return {"success": False, "updated": False, "message": f"bucket owner {owner} has no keys"}

        call = lambda method: _s3_request(
            endpoint, method, name, access_key, secret_key,
            namespace=namespace, region=region, verify=verify,
        )
        ok, status, body = call("HEAD")
        if ok:
            return {"success": True, "updated": False, "message": f"bucket {name} already exists"}
        if status not in (403, 404):
            return {
                "success": False,
                "updated": False,
                "message": f"failed to check bucket {name}: HTTP {status} {body}",
            }
        if status == 403:
            return {
                "success": True,
                "updated": False,
                "message": f"bucket {name} exists and is not owned by {owner}",
            }
        created_ok, created_status, created_body = call("PUT")
        if created_ok or created_status == 409:
            return {
                "success": True,
                "updated": created_ok,
                "message": f"bucket {name} created" if created_ok else f"bucket {name} already exists",
            }
        return {
            "success": False,
            "updated": False,
            "message": f"failed to create bucket {name}: HTTP {created_status} {created_body}",
        }
    except Exception as exc:
        return {"success": False, "updated": False, "message": str(exc)[:200]}


def _s3_policy_actions(actions):
    """Actions for an inline role policy.

    AWS CLI and s3cmd call ``GetBucketLocation`` before ``ListBucket``. A tight
    policy that omits it returns 403 on ``aws s3 ls s3://bucket/`` even when
    ``ListBucket`` is allowed. ``s3:*`` already includes it. The extra action
    does not grant object access.
    """
    actions = list(actions or ["s3:*"])
    if any(action in ("*", "s3:*") for action in actions):
        return actions
    if "s3:GetBucketLocation" not in actions:
        actions.append("s3:GetBucketLocation")
    return actions


def rgw_role_policy_present(
    namespace,
    role_name,
    policy_name,
    buckets,
    tenant="",
    actions=None,
    realm=None,
    zonegroup=None,
    zone=None,
):
    """Attach an inline S3 policy to an RGW role. buckets may be ['*'].

    A non-wildcard ``actions`` list also gets ``s3:GetBucketLocation``. Clients
    send that before listing, and it does not grant object access.
    """
    try:
        _load_k8s_config()
        actions = _s3_policy_actions(actions)
        resources = []
        for bucket in buckets:
            if bucket == "*":
                resources.extend(["arn:aws:s3:::*", "arn:aws:s3:::*/*"])
            else:
                resources.extend([
                    f"arn:aws:s3:::{bucket}",
                    f"arn:aws:s3:::{bucket}/*",
                ])
        policy = {
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Action": actions,
                "Resource": resources,
            }],
        }
        doc = json.dumps(policy)
        target = _rgw_target_args(realm, zonegroup, zone)
        current = _toolbox_radosgw(
            namespace,
            [
                "role", "policy", "get",
                "--role-name", role_name,
                "--policy-name", policy_name,
                *_tenant_args(tenant),
                *target,
            ],
        )
        current_doc = current["stdout"]
        if current["success"]:
            try:
                payload = json.loads(current["stdout"])
                current_doc = payload.get("Permission policy", current["stdout"])
            except ValueError:
                current_doc = current["stdout"]
        if current["success"] and _json_equal(current_doc, doc):
            return {
                "success": True,
                "updated": False,
                "message": f"role policy {policy_name} already matches",
            }
        attached = _toolbox_radosgw(
            namespace,
            [
                "role", "policy", "put",
                "--role-name", role_name,
                "--policy-name", policy_name,
                *_tenant_args(tenant),
                "--policy-doc", doc,
                *target,
            ],
        )
        return {
            "success": attached["success"],
            "updated": attached["success"],
            "message": (
                f"role policy {policy_name} attached to {role_name}"
                if attached["success"]
                else f"failed to attach {policy_name}: {attached['stderr'][:200]}"
            ),
        }
    except Exception as exc:
        return {"success": False, "updated": False, "message": str(exc)[:200]}


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
    Ensure a Ceph RGW user exists via Rook's CephObjectStoreUser CRD
    (https://rook.io/docs/rook/latest/CRDs/Object-Storage/ceph-object-store-user-crd/).

    Rook's operator creates the RGW user itself (no Admin Ops/Dashboard API
    calls or credentials needed from Salt) and writes the resulting S3
    access/secret key pair into a Kubernetes secret named
    ``rook-ceph-object-user-<store>-<name>`` in `namespace`.

    Note: this does NOT support subusers or a Swift "temp URL key" - Rook's
    CephObjectStoreUser CRD has no fields for either. Use
    kinetic_rook.rgw_subuser_present (Ceph Mgr Dashboard API) for subusers;
    temp-url-key remains radosgw-admin CLI only.

    name
        The CephObjectStoreUser resource name (becomes the RGW uid).

    namespace
        Namespace to create the CephObjectStoreUser in.

    store
        The CephObjectStore this user belongs to.

    display_name
        Optional display name (passed to `radosgw-admin user create
        --display-name`). Defaults to name.

    cluster_namespace
        Namespace of the parent CephCluster/CephObjectStore, if different
        from `namespace`. Requires the CephObjectStore's
        `allowUsersInNamespaces` to include `namespace`.

    capabilities
        Optional dict of admin capabilities, e.g. {"user": "*", "buckets": "*"}.
        Per Rook, capabilities can only be set at creation time - changing
        them requires deleting and re-creating the CephObjectStoreUser.

    quotas
        Optional dict, e.g. {"maxBuckets": 100, "maxSize": "10G", "maxObjects": 10000}.

    op_mask
        Optional list of allowed RGW operations, e.g. ["read", "write", "delete"].

    Returns a dict with 'success', 'updated', 'message', and 'resource'.
    """
    try:
        _load_k8s_config()
        custom_api = client.CustomObjectsApi()

        spec = {"store": store, "displayName": display_name or name}
        if cluster_namespace:
            spec["clusterNamespace"] = cluster_namespace
        if capabilities:
            spec["capabilities"] = capabilities
        if quotas:
            spec["quotas"] = quotas
        if op_mask is not None:
            spec["opMask"] = op_mask

        user_body = {
            "apiVersion": "ceph.rook.io/v1",
            "kind": "CephObjectStoreUser",
            "metadata": {
                "name": name,
                "namespace": namespace,
            },
            "spec": spec,
        }

        try:
            existing_user = custom_api.get_namespaced_custom_object(
                group="ceph.rook.io",
                version="v1",
                namespace=namespace,
                plural="cephobjectstoreusers",
                name=name,
            )
            if existing_user.get("spec") == spec:
                return {
                    "success": True,
                    "updated": False,
                    "message": f"CephObjectStoreUser {name} already exists in namespace {namespace} with matching spec.",
                    "resource": existing_user,
                }
            else:
                # Spec differs (e.g. capabilities) - Rook only applies caps at
                # creation, so delete and let the next run recreate it.
                try:
                    custom_api.delete_namespaced_custom_object(
                        group="ceph.rook.io",
                        version="v1",
                        namespace=namespace,
                        plural="cephobjectstoreusers",
                        name=name,
                    )
                    return {
                        "success": True,
                        "updated": True,
                        "message": f"CephObjectStoreUser {name} deletion initiated in namespace {namespace} (will recreate on next run).",
                        "resource": {},
                    }
                except ApiException as delete_err:
                    if delete_err.status == 409 and "object is being deleted" in str(delete_err):
                        return {
                            "success": True,
                            "updated": True,
                            "message": f"CephObjectStoreUser {name} is still terminating in namespace {namespace}; will recreate when ready.",
                            "resource": {},
                        }
                    return {
                        "success": False,
                        "updated": False,
                        "message": f"Failed to delete existing CephObjectStoreUser {name} in namespace {namespace}: {str(delete_err)[:100]}...",
                        "resource": {},
                    }
        except ApiException as e:
            if e.status == 404:
                created_user = custom_api.create_namespaced_custom_object(
                    group="ceph.rook.io",
                    version="v1",
                    namespace=namespace,
                    plural="cephobjectstoreusers",
                    body=user_body,
                )
                return {
                    "success": True,
                    "updated": True,
                    "message": f"CephObjectStoreUser {name} created in namespace {namespace}.",
                    "resource": created_user,
                }
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to manage CephObjectStoreUser {name} in namespace {namespace}: {str(e)[:100]}...",
                    "resource": {},
                }
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Error managing CephObjectStoreUser {name} in namespace {namespace}: {str(e)[:100]}...",
            "resource": {},
        }


def _mgr_dashboard_login(endpoint, username, password, verify_ssl=True, timeout=30):
    """
    Log in to the Ceph Mgr Dashboard REST API
    (https://docs.ceph.com/en/quincy/mgr/ceph_api/) and return a bearer token.
    """
    resp = requests.post(
        endpoint.rstrip("/") + "/api/auth",
        json={"username": username, "password": password},
        headers={
            "Accept": "application/vnd.ceph.api.v1.0+json",
            "Content-Type": "application/json",
        },
        verify=verify_ssl,
        timeout=timeout,
    )
    resp.raise_for_status()
    return resp.json()["token"]


def _mgr_dashboard_request(method, endpoint, token, path, params=None, json_body=None,
                           verify_ssl=True, timeout=30, api_version="1.0"):
    """Issue an authenticated request against the Ceph Mgr Dashboard REST API."""
    headers = {
        "Accept": f"application/vnd.ceph.api.v{api_version}+json",
        "Authorization": f"Bearer {token}",
    }
    if json_body is not None:
        headers["Content-Type"] = "application/json"
    return requests.request(
        method,
        endpoint.rstrip("/") + path,
        params=params,
        json=json_body,
        headers=headers,
        verify=verify_ssl,
        timeout=timeout,
    )


def rgw_subuser_present(uid, subuser, dashboard_endpoint, dashboard_username, dashboard_password,
                        access="full", generate_secret=True, secret=None,
                        verify_ssl=True, **kwargs):
    """
    Ensure an RGW subuser exists under the given uid, using the Ceph Mgr
    Dashboard REST API (https://docs.ceph.com/en/quincy/mgr/ceph_api/#rgwuser).

    Rook's CephObjectStoreUser CRD has no subuser support, and the plain RGW
    Admin Ops API requires AWS SigV4 request signing (an extra dependency) -
    the Mgr Dashboard API supports subusers with simple username/password ->
    JWT bearer-token auth instead, using only the `requests` library.

    This requires the Dashboard module to already be linked to RGW (one-time
    setup, not automated by Rook):

    .. code-block:: bash

        ceph dashboard set-rgw-api-access-key -i <accesskeyfile>
        ceph dashboard set-rgw-api-secret-key -i <secretkeyfile>
        ceph dashboard set-rgw-api-host <rgw-service>
        ceph dashboard set-rgw-api-port <port>
        ceph dashboard set-rgw-api-scheme http

    uid
        Parent user ID (must already exist, e.g. via
        kinetic_rook.ceph_object_store_user_present).

    subuser
        Subuser name (e.g. "glance:swift").

    dashboard_endpoint
        Base URL of the Ceph Mgr Dashboard (e.g.
        "https://rook-ceph-mgr-dashboard.rook-ceph.svc:8443").

    dashboard_username / dashboard_password
        Credentials of a Dashboard user with RGW management permissions
        (e.g. the built-in "admin" user Rook provisions).

    access
        Access level (read, write, readwrite, full).

    generate_secret / secret
        Same semantics as keys above.

    verify_ssl
        Whether to verify TLS certificates when calling the endpoint.

    Note: setting a Swift "temp URL key" is NOT supported here either - it
    is not exposed by the Dashboard API's RgwUser endpoints, only by the
    radosgw-admin CLI.
    """
    try:
        token = _mgr_dashboard_login(
            dashboard_endpoint, dashboard_username, dashboard_password, verify_ssl=verify_ssl,
        )
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to authenticate to Ceph Dashboard at {dashboard_endpoint}: {e}",
        }

    try:
        resp = _mgr_dashboard_request(
            "GET", dashboard_endpoint, token, f"/api/rgw/user/{uid}", verify_ssl=verify_ssl,
        )
        if resp.status_code == 404:
            return {
                "success": False,
                "updated": False,
                "message": f"RGW user {uid} does not exist; cannot create subuser {subuser}.",
            }
        resp.raise_for_status()
        info = resp.json()
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to query RGW user {uid}: {e}",
        }

    existing = any(s.get("id") == subuser for s in info.get("subusers", []))

    if not existing:
        body = {"subuser": subuser, "access": access}
        if generate_secret:
            body["generate_secret"] = "true"
        elif secret:
            body["generate_secret"] = "false"
            body["secret_key"] = secret

        try:
            resp = _mgr_dashboard_request(
                "POST", dashboard_endpoint, token, f"/api/rgw/user/{uid}/subuser",
                json_body=body, verify_ssl=verify_ssl,
            )
            resp.raise_for_status()
        except Exception as e:
            return {
                "success": False,
                "updated": False,
                "message": f"Failed to create RGW subuser {subuser}: {e}",
            }

    return {
        "success": True,
        "updated": not existing,
        "message": f"RGW subuser {subuser} ensured.",
    }
