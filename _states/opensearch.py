# -*- coding: utf-8 -*-
"""
SaltStack state module for managing OpenSearch resources using the kinetic-os execution module.

This module provides states for managing OpenSearch indices, roles, and user mappings.
It interacts with the OpenSearch API to ensure the desired state of these resources.
"""

import copy

__virtualname__ = 'opensearch'

def __virtual__():
    """
    Check if the kinetic-os execution module is available.
    """
    if 'kinetic-os.check_health' in __salt__:
        return __virtualname__
    return (False, 'The kinetic-os execution module is not available. Ensure requests library is installed.')

def index_present(name, index_name, admin_user='admin', admin_password=None, host='https://api.logger.services.gacyberrange.org:443', shards=1, replicas=1):
    """
    Ensure that an index exists in OpenSearch. If it does not exist, create it with the specified settings.

    name
        The name of the state (arbitrary, for SaltStack identification).

    index_name
        The name of the index to create. Defaults to 'kvm-logs'.

    admin_user
        The admin username for authentication. Defaults to 'admin'.

    admin_password
        The admin password for authentication. If None, retrieved from pillar.

    host
        The OpenSearch host URL. Defaults to 'https://api.logger.services.gacyberrange.org:443'.

    shards
        Number of shards for the index. Defaults to 1.

    replicas
        Number of replicas for the index. Defaults to 1.

    Example:
    .. code-block:: yaml

        ensure_kvm_logs_index:
          opensearch.index_present:
            - index_name: kvm-logs
            - admin_user: admin
            - shards: 1
            - replicas: 1
    """
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        result = __salt__['kinetic-os.create_index'](
            index_name=index_name,
            admin_user=admin_user,
            admin_password=admin_password,
            host=host,
            shards=shards,
            replicas=replicas
        )
        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['created']:
            ret['changes'] = {'index_created': True}
        else:
            ret['changes'] = {}
    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure index {index_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret

def role_present(name, index_name=None, role_name='fluentbit_role', namespace='efk', cluster_name='opensearch', cluster_permissions=None, index_allowed_actions=None, tenant_patterns=None, tenant_allowed_actions=None, index_patterns=None):
    """
    Ensure that an OpensearchRole Custom Resource exists with permissions for a specific index.

    This is reconciled by the OpenSearch Kubernetes Operator (opensearch.org/v1
    OpensearchRole) instead of calling the OpenSearch Security REST API directly.

    name
        The name of the state (arbitrary, for SaltStack identification).

    role_name
        The name of the OpensearchRole resource (and resulting OpenSearch role).
        Must be a valid DNS-1123 name. Defaults to 'fluentbit_role'.

    index_name
        The name/pattern prefix of the index to grant permissions on. A trailing
        "*" is appended automatically. Ignored when index_patterns is set.

    index_patterns
        Optional list of exact index patterns (no auto-appended "*").

    namespace
        The Kubernetes namespace to create the OpensearchRole in. Must match the
        namespace of the OpenSearchCluster. Defaults to 'efk'.

    cluster_name
        The name of the OpenSearchCluster this role applies to. Defaults to 'opensearch'.

    cluster_permissions
        Optional list of cluster-level permissions. Defaults to
        ['cluster_composite_ops', 'indices_monitor'].

    index_allowed_actions
        Optional list of allowed actions for the index pattern.

    tenant_patterns
        Optional list of tenant patterns to grant tenant permissions for.

    tenant_allowed_actions
        Optional list of allowed actions for the tenant patterns.

    Example:
    .. code-block:: yaml

        ensure_fluentbit_role:
          opensearch.role_present:
            - role_name: fluentbit_role
            - index_name: kvm-logs
            - namespace: efk
            - cluster_name: opensearch
    """
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        result = __salt__['kinetic-os.create_role'](
            role_name=role_name,
            index_name=index_name,
            namespace=namespace,
            cluster_name=cluster_name,
            cluster_permissions=cluster_permissions,
            index_allowed_actions=index_allowed_actions,
            tenant_patterns=tenant_patterns,
            tenant_allowed_actions=tenant_allowed_actions,
            index_patterns=index_patterns,
        )
        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['updated']:
            ret['changes'] = {'role_updated': True}
        else:
            ret['changes'] = {}
    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure role {role_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret

def user_role_mapping_present(name, role_name='fluentbit_role', user_name=None, namespace='efk', cluster_name='opensearch', backend_roles=None):
    """
    Ensure that a user is mapped to a role in OpenSearch.

    This is reconciled by the OpenSearch Kubernetes Operator (opensearch.org/v1
    OpensearchUserRoleBinding) instead of calling the OpenSearch Security REST
    API directly.

    name
        The name of the state (arbitrary, for SaltStack identification).

    role_name
        The name of the role to map the user to. Defaults to 'fluentbit_role'.

    user_name
        The name of the user to map to the role. Optional when backend_roles is set.

    namespace
        The Kubernetes namespace to create the OpensearchUserRoleBinding in. Must
        match the namespace of the OpenSearchCluster. Defaults to 'efk'.

    cluster_name
        The name of the OpenSearchCluster this binding applies to. Defaults to 'opensearch'.

    backend_roles
        Optional list of backend roles to bind to the role (may be used without user_name).

    Example:
    .. code-block:: yaml

        ensure_fluentbit_mapping:
          opensearch.user_role_mapping_present:
            - role_name: fluentbit_role
            - user_name: fluentbit
            - namespace: efk
            - cluster_name: opensearch
    """
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        result = __salt__['kinetic-os.map_user_to_role'](
            role_name=role_name,
            user_name=user_name,
            namespace=namespace,
            cluster_name=cluster_name,
            backend_roles=backend_roles,
        )
        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['updated']:
            ret['changes'] = {'mapping_updated': True}
        else:
            ret['changes'] = {}
    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure mapping for role {role_name}: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret

def cluster_health(name, admin_user='admin', admin_password=None, host='https://api.logger.services.gacyberrange.org:443'):
    """
    Check if the OpenSearch cluster is healthy (status is green or yellow).

    name
        The name of the state (arbitrary, for SaltStack identification).

    admin_user
        The admin username for authentication. Defaults to 'admin'.

    admin_password
        The admin password for authentication. If None, retrieved from pillar.

    host
        The OpenSearch host URL. Defaults to 'https://api.logger.services.gacyberrange.org:443'.

    Example:
    .. code-block:: yaml

        check_os_health:
          opensearch.cluster_healthy:
            - admin_user: admin
    """
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        result = __salt__['kinetic-os.check_health'](
            admin_user=admin_user,
            admin_password=admin_password,
            host=host
        )
        ret['result'] = result['success'] and result['healthy']
        ret['comment'] = result['message']
        ret['changes'] = {}
    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to check OpenSearch cluster health: {str(e)[:100]}..."
        ret['changes'] = {}

    return ret


# Hardcoded query/schedule for 3.3.4 keycloak-index-freshness (OpenSearch 2.11).
# enabled and actions come from pillar opensearch_alerting:freshness_monitor.
_KEYCLOAK_FRESHNESS_MONITOR = {
    "type": "monitor",
    "name": "keycloak-index-freshness",
    "monitor_type": "query_level_monitor",
    "schedule": {"period": {"interval": 5, "unit": "MINUTES"}},
    "inputs": [
        {
            "search": {
                "indices": ["keycloak-logs-*"],
                "query": {
                    "size": 0,
                    "query": {
                        "range": {"@timestamp": {"gte": "now-15m"}}
                    },
                },
            }
        }
    ],
    "triggers": [
        {
            "name": "no-docs-15m",
            "severity": "1",
            "condition": {
                "script": {
                    "source": "ctx.results[0].hits.total.value < 1",
                    "lang": "painless",
                }
            },
            "actions": [],
        }
    ],
}


def _freshness_monitor_actions(cfg):
    """
    Build trigger actions from pillar opensearch_alerting:freshness_monitor.

    Default destination type is email. Empty actions if pillar has no To: and
    no destination id (kinetic-pillar can fill these later).
    """
    if not isinstance(cfg, dict):
        return []
    if "actions" in cfg:
        return cfg.get("actions") or []

    dest = cfg.get("destination") or {}
    if not isinstance(dest, dict):
        dest = {}
    dest_type = dest.get("type") or "email"
    dest_id = dest.get("id") or dest.get("destination_id") or cfg.get("destination_id")
    to_list = dest.get("to") or dest.get("recipients") or cfg.get("to") or []
    if isinstance(to_list, str):
        to_list = [to_list]
    # Empty actions is OK if pillar has no To: yet (and no destination id).
    if not dest_id or not to_list:
        return []

    action = {
        "name": dest.get("action_name", "notify"),
        "destination_id": dest_id,
        "message_template": {
            "source": dest.get(
                "message",
                "No documents written to keycloak-logs-* in the last 15 minutes.",
            ),
            "lang": "mustache",
        },
    }
    if dest_type == "email" or dest.get("subject"):
        action["subject_template"] = {
            "source": dest.get("subject", "Keycloak index freshness alert"),
            "lang": "mustache",
        }
    return [action]


def monitor_present(
    name,
    monitor_name="keycloak-index-freshness",
    admin_user="admin",
    admin_password=None,
    host="https://api.logger.services.gacyberrange.org:443",
):
    """
    Ensure the keycloak-index-freshness Alerting monitor exists (3.3.4).

    Query and schedule are hardcoded. enabled and destination/actions are read
    from pillar opensearch_alerting:freshness_monitor. Lists monitors with
    POST /_plugins/_alerting/monitors/_search — never GET
    /_plugins/_alerting/monitors (405 on OpenSearch 2.11).

    name
        The name of the state (arbitrary, for SaltStack identification).

    monitor_name
        Monitor name. Defaults to 'keycloak-index-freshness'.

    admin_user
        Admin username. Defaults to 'admin'.

    admin_password
        Admin password. If None, retrieved from pillar.

    host
        OpenSearch host URL.
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        cfg = __salt__["pillar.get"]("opensearch_alerting:freshness_monitor", {}) or {}
        body = copy.deepcopy(_KEYCLOAK_FRESHNESS_MONITOR)
        body["name"] = monitor_name
        body["enabled"] = cfg.get("enabled", True)
        body["triggers"][0]["actions"] = _freshness_monitor_actions(cfg)

        result = __salt__["kinetic-os.ensure_monitor"](
            monitor_name=monitor_name,
            monitor_body=body,
            admin_user=admin_user,
            admin_password=admin_password,
            host=host,
        )
        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result.get("updated"):
            ret["changes"] = {"monitor_updated": True}
        else:
            ret["changes"] = {}
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure monitor {monitor_name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret
