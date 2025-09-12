# -*- coding: utf-8 -*-
"""
SaltStack execution module for interacting with OpenSearch API.

This module provides functions to manage OpenSearch resources like indices, roles, and user mappings.
"""

import requests
import json
from requests.auth import HTTPBasicAuth

__virtualname__ = 'kinetic-os'

def __virtual__():
    """
    Check if the requests library is available.
    """
    try:
        import requests
        return __virtualname__
    except ImportError:
        return (False, 'The requests library is not installed. Please install it using "pip install requests".')

def check_health(admin_user='admin', admin_password=None, host='https://api.logger.services.gacyberrange.org:443'):
    """
    Check the health of the OpenSearch cluster.
    """
    try:
        if admin_password is None:
            admin_password = __salt__['pillar.get']('opensearch_admin_password', '')
        url = f"{host}/_cluster/health"
        response = requests.get(url, auth=HTTPBasicAuth(admin_user, admin_password), verify=False)
        response.raise_for_status()
        data = response.json()
        status = data.get('status', 'unknown')
        healthy = status in ['green', 'yellow']
        return {
            'success': True,
            'healthy': healthy,
            'message': f"Cluster health: {status}"
        }
    except Exception as e:
        return {
            'success': False,
            'healthy': False,
            'message': f"Failed to check cluster health: {str(e)[:100]}..."
        }

def create_index(index_name='kvm-logs', admin_user='admin', admin_password=None, host='https://api.logger.services.gacyberrange.org:443', shards=1, replicas=1):
    """
    Create an index in OpenSearch if it doesn't exist.
    """
    try:
        if admin_password is None:
            admin_password = __salt__['pillar.get']('opensearch_admin_password', '')
        url = f"{host}/{index_name}"
        # Check if index exists
        check_response = requests.head(url, auth=HTTPBasicAuth(admin_user, admin_password), verify=False)
        if check_response.status_code == 200:
            return {
                'success': True,
                'created': False,
                'message': f"Index {index_name} already exists"
            }
        # Create index if it doesn't exist
        payload = {
            "settings": {
                "index": {
                    "number_of_shards": shards,
                    "number_of_replicas": replicas
                }
            },
            "mappings": {
                "dynamic": "true",
                "_source": {
                    "enabled": True
                },
                "properties": {
                    "time": {
                        "type": "date",
                        "format": "yyyy-MM-dd'T'HH:mm:ss.SSSZ||epoch_millis"
                    },
                    "log": {
                        "type": "text"
                    },
                    "tag": {
                        "type": "keyword"
                    }
                }
            }
        }
        response = requests.put(url, auth=HTTPBasicAuth(admin_user, admin_password), json=payload, verify=False)
        response.raise_for_status()
        return {
            'success': True,
            'created': True,
            'message': f"Index {index_name} created successfully"
        }
    except Exception as e:
        return {
            'success': False,
            'created': False,
            'message': f"Failed to create index {index_name}: {str(e)[:100]}..."
        }

def create_role(role_name='fluentbit_role', index_name='kvm-logs', admin_user='admin', admin_password=None, host='https://api.logger.services.gacyberrange.org:443'):
    """
    Create or update a role in OpenSearch with permissions for a specific index.
    """
    try:
        if admin_password is None:
            admin_password = __salt__['pillar.get']('admin_password', '')
        url = f"{host}/_plugins/_security/api/roles/{role_name}"
        payload = f'
            {
            "cluster_permissions": [
                "cluster_composite_ops",
                "indices_monitor"
            ],
            "index_permissions": [{
                "index_patterns": [
                "{index_name}*"
                ],
                "dls": "",
                "fls": [],
                "masked_fields": [],
                "allowed_actions": [
                "read"
                ]
            }],
            "tenant_permissions": [{
                "tenant_patterns": [
                "human_resources"
                ],
                "allowed_actions": [
                "kibana_all_read"
                ]
            }]
            }
            '
        response = requests.put(url, auth=HTTPBasicAuth(admin_user, admin_password), json=payload, verify=False)
        response.raise_for_status()
        return {
            'success': True,
            'updated': True,
            'message': f"Role {role_name} created or updated successfully"
        }
    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Failed to create/update role {role_name}: {response.status_code if 'response' in locals() else 'N/A'} - {str(e)[:100]}..."
        }

def map_user_to_role(role_name='fluentbit_role', user_name='fluentbit', admin_user='admin', admin_password=None, host='https://api.logger.services.gacyberrange.org:443'):
    """
    Map a user to a role in OpenSearch.
    """
    try:
        if admin_password is None:
            admin_password = __salt__['pillar.get']('opensearch_admin_password', '')
        url = f"{host}/_plugins/_security/api/rolesmapping/{role_name}"
        payload = {
            "users": [user_name]
        }
        response = requests.put(url, auth=HTTPBasicAuth(admin_user, admin_password), json=payload, verify=False)
        response.raise_for_status()
        return {
            'success': True,
            'updated': True,
            'message': f"User {user_name} mapped to role {role_name} successfully"
        }
    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Failed to map user {user_name} to role {role_name}: {str(e)[:100]}..."
        }