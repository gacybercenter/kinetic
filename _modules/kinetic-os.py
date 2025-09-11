# -*- coding: utf-8 -*-
"""
SaltStack execution module for interacting with OpenSearch API.

This module provides functions to manage OpenSearch resources such as indices, roles, and user mappings.
It uses the requests library to make HTTP calls to the OpenSearch REST API for operations like creating indices
and setting up permissions for users.
"""

import salt.utils.decorators as decorators
import requests
import json
from requests.auth import HTTPBasicAuth

# Ensure Salt can find this module
__virtualname__ = 'kinetic-os'

@decorators.memoize
def __virtual__():
    """
    Check if the requests library is available.
    """
    try:
        import requests
        return __virtualname__
    except ImportError:
        return (False, 'The requests library is not installed. Please install it using "pip install requests".')

def create_index(index_name='kvm-logs', admin_user='admin', admin_password=None, host='https://api.logger.services.gacyberrange.org:443', shards=1, replicas=1):
    """
    Create an index in OpenSearch if it doesn't exist using admin credentials.

    Args:
        index_name (str): The name of the index to create. Defaults to 'kvm-logs'.
        admin_user (str): The admin username for authentication. Defaults to 'admin'.
        admin_password (str): The admin password for authentication. If None, retrieved from pillar.
        host (str): The OpenSearch host URL. Defaults to 'https://api.logger.services.gacyberrange.org:443'.
        shards (int): Number of shards for the index. Defaults to 1.
        replicas (int): Number of replicas for the index. Defaults to 1.

    Returns:
        dict: A dictionary with 'success' (bool), 'created' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-os.create_index kvm-logs admin mypassword
    """
    try:
        # Retrieve admin password from pillar if not provided
        if admin_password is None:
            admin_password = __salt__['pillar.get']('admin_password', __salt__['pillar.get']('fluentd_password', ''))

        if not admin_password:
            return {
                'success': False,
                'created': False,
                'message': 'Admin password not provided and not found in pillar'
            }

        # Check if index exists
        url = f"{host}/{index_name}"
        auth = HTTPBasicAuth(admin_user, admin_password)
        response = requests.head(url, auth=auth, verify=False)

        if response.status_code == 200:
            return {
                'success': True,
                'created': False,
                'message': f"Index {index_name} already exists"
            }

        # Create index if it doesn't exist
        if response.status_code == 404:
            data = {
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
            response = requests.put(url, auth=auth, json=data, verify=False)
            if response.status_code in [200, 201]:
                return {
                    'success': True,
                    'created': True,
                    'message': f"Index {index_name} created successfully"
                }
            else:
                return {
                    'success': False,
                    'created': False,
                    'message': f"Failed to create index {index_name}: {response.status_code} - {response.text[:100]}..."
                }
        else:
            return {
                'success': False,
                'created': False,
                'message': f"Unexpected status code checking index {index_name}: {response.status_code}"
            }

    except Exception as e:
        return {
            'success': False,
            'created': False,
            'message': f"Error creating index {index_name}: {str(e)[:100]}..."
        }

def create_role(role_name='fluentbit_role', index_name='kvm-logs', admin_user='admin', admin_password=None, host='https://api.logger.services.gacyberrange.org:443'):
    """
    Create or update a role in OpenSearch with permissions for a specific index.

    Args:
        role_name (str): The name of the role to create or update. Defaults to 'fluentbit_role'.
        index_name (str): The name of the index to grant permissions on. Defaults to 'kvm-logs'.
        admin_user (str): The admin username for authentication. Defaults to 'admin'.
        admin_password (str): The admin password for authentication. If None, retrieved from pillar.
        host (str): The OpenSearch host URL. Defaults to 'https://api.logger.services.gacyberrange.org:443'.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-os.create_role fluentbit_role kvm-logs admin mypassword
    """
    try:
        # Retrieve admin password from pillar if not provided
        if admin_password is None:
            admin_password = __salt__['pillar.get']('admin_password', __salt__['pillar.get']('fluentd_password', ''))

        if not admin_password:
            return {
                'success': False,
                'updated': False,
                'message': 'Admin password not provided and not found in pillar'
            }

        url = f"{host}/_plugins/_security/api/roles/{role_name}"
        auth = HTTPBasicAuth(admin_user, admin_password)
        data = {
            "cluster_permissions": ["cluster_composite_ops", "cluster_monitor"],
            "index_permissions": {
                index_name: {
                    "index_patterns": [f"{index_name}*"],
                    "allowed_actions": ["write", "read", "create_index", "indices:data/write/bulk"]
                }
            }
        }
        response = requests.put(url, auth=auth, json=data, verify=False)
        if response.status_code in [200, 201]:
            return {
                'success': True,
                'updated': True,
                'message': f"Role {role_name} created or updated for index {index_name}"
            }
        else:
            return {
                'success': False,
                'updated': False,
                'message': f"Failed to create/update role {role_name}: {response.status_code} - {response.text[:100]}..."
            }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Error creating/updating role {role_name}: {str(e)[:100]}..."
        }

def map_user_to_role(role_name='fluentbit_role', user_name='fluentbit', admin_user='admin', admin_password=None, host='https://api.logger.services.gacyberrange.org:443'):
    """
    Map a user to a role in OpenSearch.

    Args:
        role_name (str): The name of the role to map the user to. Defaults to 'fluentbit_role'.
        user_name (str): The name of the user to map to the role. Defaults to 'fluentbit'.
        admin_user (str): The admin username for authentication. Defaults to 'admin'.
        admin_password (str): The admin password for authentication. If None, retrieved from pillar.
        host (str): The OpenSearch host URL. Defaults to 'https://api.logger.services.gacyberrange.org:443'.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-os.map_user_to_role fluentbit_role fluentbit admin mypassword
    """
    try:
        # Retrieve admin password from pillar if not provided
        if admin_password is None:
            admin_password = __salt__['pillar.get']('admin_password', __salt__['pillar.get']('fluentd_password', ''))

        if not admin_password:
            return {
                'success': False,
                'updated': False,
                'message': 'Admin password not provided and not found in pillar'
            }

        url = f"{host}/_plugins/_security/api/rolesmapping/{role_name}"
        auth = HTTPBasicAuth(admin_user, admin_password)
        data = {
            "users": [user_name]
        }
        response = requests.put(url, auth=auth, json=data, verify=False)
        if response.status_code in [200, 201]:
            return {
                'success': True,
                'updated': True,
                'message': f"User {user_name} mapped to role {role_name}"
            }
        else:
            return {
                'success': False,
                'updated': False,
                'message': f"Failed to map user {user_name} to role {role_name}: {response.status_code} - {response.text[:100]}..."
            }

    except Exception as e:
        return {
            'success': False,
            'updated': False,
            'message': f"Error mapping user {user_name} to role {role_name}: {str(e)[:100]}..."
        }

def check_health(admin_user='admin', admin_password=None, host='https://api.logger.services.gacyberrange.org:443'):
    """
    Check the health of the OpenSearch cluster.

    Args:
        admin_user (str): The admin username for authentication. Defaults to 'admin'.
        admin_password (str): The admin password for authentication. If None, retrieved from pillar.
        host (str): The OpenSearch host URL. Defaults to 'https://api.logger.services.gacyberrange.org:443'.

    Returns:
        dict: A dictionary with 'success' (bool), 'healthy' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-os.check_health admin mypassword
    """
    try:
        # Retrieve admin password from pillar if not provided
        if admin_password is None:
            admin_password = __salt__['pillar.get']('admin_password', __salt__['pillar.get']('fluentd_password', ''))

        if not admin_password:
            return {
                'success': False,
                'healthy': False,
                'message': 'Admin password not provided and not found in pillar'
            }

        url = f"{host}/_cluster/health"
        auth = HTTPBasicAuth(admin_user, admin_password)
        response = requests.get(url, auth=auth, verify=False)
        if response.status_code == 200:
            health_data = response.json()
            status = health_data.get('status', 'unknown')
            healthy = status in ['green', 'yellow']
            return {
                'success': True,
                'healthy': healthy,
                'message': f"OpenSearch cluster health: {status}"
            }
        else:
            return {
                'success': False,
                'healthy': False,
                'message': f"Failed to check cluster health: {response.status_code} - {response.text[:100]}..."
            }

    except Exception as e:
        return {
            'success': False,
            'healthy': False,
            'message': f"Error checking cluster health: {str(e)[:100]}..."
        }