# -*- coding: utf-8 -*-
"""
SaltStack execution module for interacting with OpenSearch.

This module provides functions to manage OpenSearch resources like indices,
roles, and user mappings.

Roles and user/role bindings are managed via the OpenSearch Kubernetes
Operator's Custom Resources (OpensearchRole, OpensearchUserRoleBinding -
opensearch.org/v1) instead of calling the OpenSearch Security REST API
directly. Index creation and cluster health checks have no equivalent CRD in
the operator (only OpensearchIndexTemplate/OpensearchComponentTemplate exist
for templates, not one-off indices), so those still talk to the OpenSearch
HTTP API directly.
"""

import json

import requests
from requests.auth import HTTPBasicAuth

try:
    from kubernetes import client, config
    from kubernetes.client.rest import ApiException

    HAS_KUBERNETES = True
except ImportError:
    HAS_KUBERNETES = False

__virtualname__ = "kinetic-os"


def __virtual__():
    """
    Check if the requests library is available.
    """
    try:
        import requests

        return __virtualname__
    except ImportError:
        return (
            False,
            'The requests library is not installed. Please install it using "pip install requests".',
        )


def _load_k8s_config():
    """Load Kubernetes configuration, preferring in-cluster config then kubeconfig."""
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()


def check_health(
    admin_user="admin",
    admin_password=None,
    host="https://api.logger.services.gacyberrange.org:443",
):
    """
    Check the health of the OpenSearch cluster.
    """
    try:
        if admin_password is None:
            admin_password = __salt__["pillar.get"]("opensearch_admin_password", "")
        url = f"{host}/_cluster/health"
        response = requests.get(
            url, auth=HTTPBasicAuth(admin_user, admin_password), verify=False
        )
        response.raise_for_status()
        data = response.json()
        status = data.get("status", "unknown")
        healthy = status in ["green", "yellow"]
        return {
            "success": True,
            "healthy": healthy,
            "message": f"Cluster health: {status}",
        }
    except Exception as e:
        return {
            "success": False,
            "healthy": False,
            "message": f"Failed to check cluster health: {str(e)[:100]}...",
        }


def create_index(
    index_name,
    admin_user="admin",
    admin_password=None,
    host="https://api.logger.services.gacyberrange.org:443",
    shards=1,
    replicas=1,
):
    """
    Create an index in OpenSearch if it doesn't exist.
    """
    try:
        if admin_password is None:
            admin_password = __salt__["pillar.get"]("opensearch_admin_password", "")
        url = f"{host}/{index_name}"
        # Check if index exists
        check_response = requests.head(
            url, auth=HTTPBasicAuth(admin_user, admin_password), verify=False
        )
        if check_response.status_code == 200:
            return {
                "success": True,
                "created": False,
                "message": f"Index {index_name} already exists",
            }
        # Create index if it doesn't exist
        payload = {
            "settings": {
                "index": {"number_of_shards": shards, "number_of_replicas": replicas}
            },
            "mappings": {
                "dynamic": "true",
                "_source": {"enabled": True},
                "properties": {
                    "time": {
                        "type": "date",
                        "format": "yyyy-MM-dd'T'HH:mm:ss.SSSZ||epoch_millis",
                    },
                    "log": {"type": "text"},
                    "tag": {"type": "keyword"},
                },
            },
        }
        response = requests.put(
            url,
            auth=HTTPBasicAuth(admin_user, admin_password),
            json=payload,
            verify=False,
        )
        response.raise_for_status()
        return {
            "success": True,
            "created": True,
            "message": f"Index {index_name} created successfully",
        }
    except Exception as e:
        return {
            "success": False,
            "created": False,
            "message": f"Failed to create index {index_name}: {str(e)[:100]}...",
        }


def create_role(
    index_name,
    role_name="fluentbit_role",
    namespace="efk",
    cluster_name="opensearch",
    cluster_permissions=None,
    index_allowed_actions=None,
    tenant_patterns=None,
    tenant_allowed_actions=None,
):
    """
    Ensure an OpensearchRole Custom Resource exists with permissions for a specific index.

    This creates/updates an `OpensearchRole` (opensearch.org/v1) Custom Resource that the
    OpenSearch Kubernetes Operator reconciles into the cluster's security config, instead
    of calling the OpenSearch Security REST API directly.

    Args:
        index_name (str): Index name/pattern prefix to grant permissions on. A trailing
            "*" is appended automatically (e.g. "openldap-audit-logs-" becomes
            "openldap-audit-logs-*").
        role_name (str): Name of the OpensearchRole resource (and the resulting
            OpenSearch role).
        namespace (str): Namespace to create the OpensearchRole in. Must match the
            namespace of the OpenSearchCluster it targets.
        cluster_name (str): Name of the OpenSearchCluster this role applies to.
        cluster_permissions (list, optional): Cluster-level permissions. Defaults to
            ["cluster_composite_ops", "indices_monitor"].
        index_allowed_actions (list, optional): Allowed actions for the index pattern.
            Defaults to a standard read/write/manage/create set.
        tenant_patterns (list, optional): Tenant patterns to grant tenant permissions for.
            If omitted, no tenantPermissions block is added.
        tenant_allowed_actions (list, optional): Allowed actions for the tenant patterns.
            Defaults to ["kibana_all_read"] when tenant_patterns is set.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).
    """
    if not HAS_KUBERNETES:
        return {
            "success": False,
            "updated": False,
            "message": 'The kubernetes python library is not installed. Please install it using "pip install kubernetes".',
        }

    try:
        _load_k8s_config()
        custom_api = client.CustomObjectsApi()
        group = "opensearch.org"
        version = "v1"
        plural = "opensearchroles"

        spec = {
            "opensearchCluster": {"name": cluster_name},
            "clusterPermissions": cluster_permissions
            or ["cluster_composite_ops", "indices_monitor"],
            "indexPermissions": [
                {
                    "indexPatterns": [f"{index_name}*"],
                    "allowedActions": index_allowed_actions
                    or [
                        "read",
                        "write",
                        "manage",
                        "indices:data/write/index",
                        "indices:data/write/bulk",
                        "indices:admin/create",
                    ],
                }
            ],
        }
        if tenant_patterns:
            spec["tenantPermissions"] = [
                {
                    "tenantPatterns": tenant_patterns,
                    "allowedActions": tenant_allowed_actions or ["kibana_all_read"],
                }
            ]

        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "OpensearchRole",
            "metadata": {"name": role_name, "namespace": namespace},
            "spec": spec,
        }

        try:
            existing = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=role_name,
            )
            if existing.get("spec") == spec:
                return {
                    "success": True,
                    "updated": False,
                    "message": f"OpensearchRole {role_name} already up-to-date",
                }
            body["metadata"]["resourceVersion"] = existing["metadata"][
                "resourceVersion"
            ]
            custom_api.replace_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=role_name,
                body=body,
            )
            return {
                "success": True,
                "updated": True,
                "message": f"OpensearchRole {role_name} updated",
            }
        except ApiException as e:
            if e.status == 404:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=body,
                )
                return {
                    "success": True,
                    "updated": True,
                    "message": f"OpensearchRole {role_name} created",
                }
            return {
                "success": False,
                "updated": False,
                "message": f"Failed to create/update OpensearchRole {role_name}: {str(e)}",
            }
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to create/update OpensearchRole {role_name}: {str(e)}",
        }


def map_user_to_role(
    role_name="fluentbit_role",
    user_name="fluentbit",
    namespace="efk",
    cluster_name="opensearch",
    backend_roles=None,
):
    """
    Ensure an OpensearchUserRoleBinding Custom Resource maps a user to a role.

    This creates/updates an `OpensearchUserRoleBinding` (opensearch.org/v1) Custom
    Resource that the OpenSearch Kubernetes Operator reconciles into the cluster's
    security config, instead of calling the OpenSearch Security REST API directly.

    Args:
        role_name (str): Name of the OpensearchRole (or built-in role) to bind.
        user_name (str): Name of the OpenSearch user to bind to the role.
        namespace (str): Namespace to create the OpensearchUserRoleBinding in. Must
            match the namespace of the OpenSearchCluster it targets.
        cluster_name (str): Name of the OpenSearchCluster this binding applies to.
        backend_roles (list, optional): Backend roles to also bind to the role.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).
    """
    if not HAS_KUBERNETES:
        return {
            "success": False,
            "updated": False,
            "message": 'The kubernetes python library is not installed. Please install it using "pip install kubernetes".',
        }

    binding_name = f"{role_name}-{user_name}"

    try:
        _load_k8s_config()
        custom_api = client.CustomObjectsApi()
        group = "opensearch.org"
        version = "v1"
        plural = "opensearchuserrolebindings"

        spec = {
            "opensearchCluster": {"name": cluster_name},
            "roles": [role_name],
            "users": [user_name],
        }
        if backend_roles:
            spec["backendRoles"] = backend_roles

        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "OpensearchUserRoleBinding",
            "metadata": {"name": binding_name, "namespace": namespace},
            "spec": spec,
        }

        try:
            existing = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=binding_name,
            )
            if existing.get("spec") == spec:
                return {
                    "success": True,
                    "updated": False,
                    "message": f"OpensearchUserRoleBinding {binding_name} already up-to-date",
                }
            body["metadata"]["resourceVersion"] = existing["metadata"][
                "resourceVersion"
            ]
            custom_api.replace_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=binding_name,
                body=body,
            )
            return {
                "success": True,
                "updated": True,
                "message": f"OpensearchUserRoleBinding {binding_name} updated",
            }
        except ApiException as e:
            if e.status == 404:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=body,
                )
                return {
                    "success": True,
                    "updated": True,
                    "message": f"OpensearchUserRoleBinding {binding_name} created",
                }
            return {
                "success": False,
                "updated": False,
                "message": f"Failed to create/update OpensearchUserRoleBinding {binding_name}: {str(e)[:150]}",
            }
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to create/update OpensearchUserRoleBinding {binding_name}: {str(e)[:150]}",
        }
