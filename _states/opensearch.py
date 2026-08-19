# -*- coding: utf-8 -*-
"""
SaltStack state module for managing OpenSearch resources using the kinetic-os execution module.

This module provides states for managing OpenSearch indices, roles, and user mappings.
It interacts with the OpenSearch API to ensure the desired state of these resources.
"""

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

def role_present(name, index_name, role_name='fluentbit_role', namespace='efk', cluster_name='opensearch', cluster_permissions=None, index_allowed_actions=None, tenant_patterns=None, tenant_allowed_actions=None):
    """
    Ensure that an OpensearchRole Custom Resource exists with permissions for a specific index.

    This is reconciled by the OpenSearch Kubernetes Operator (opensearch.org/v1
    OpensearchRole) instead of calling the OpenSearch Security REST API directly.

    name
        The name of the state (arbitrary, for SaltStack identification).

    role_name
        The name of the OpensearchRole resource (and resulting OpenSearch role).
        Defaults to 'fluentbit_role'.

    index_name
        The name/pattern prefix of the index to grant permissions on. A trailing
        "*" is appended automatically.

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

def user_role_mapping_present(name, role_name='fluentbit_role', user_name='fluentbit', namespace='efk', cluster_name='opensearch', backend_roles=None):
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
        The name of the user to map to the role. Defaults to 'fluentbit'.

    namespace
        The Kubernetes namespace to create the OpensearchUserRoleBinding in. Must
        match the namespace of the OpenSearchCluster. Defaults to 'efk'.

    cluster_name
        The name of the OpenSearchCluster this binding applies to. Defaults to 'opensearch'.

    backend_roles
        Optional list of backend roles to also bind to the role.

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
        ret['comment'] = f"Failed to ensure user {user_name} mapping to role {role_name}: {str(e)[:100]}..."
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