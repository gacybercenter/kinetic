# -*- coding: utf-8 -*-
"""
Custom SaltStack module for LDAP operations using salt.modules.ldap3
"""

import logging

import salt.modules.ldap3 as ldap3

log = logging.getLogger(__name__)

__virtualname__ = "ldap_utils"

# In-memory cache for connection objects during a single Salt run
_CONNECTION_CACHE = {}


def __virtual__():
    """
    Only load if ldap3 module is available
    """
    if "ldap3.search" in __salt__:
        return __virtualname__
    return False, "ldap3 module not available"


def create_connect_spec(spec_name, connection_dict):
    """
    Create or update a connection specification for LDAP operations.
    If a connection with the given spec_name already exists in cache, it will not be recreated.

    Args:
        spec_name (str): The name of the connection specification.
        connection_dict (dict): Dictionary with connection parameters:
            - url (str): LDAP server URL (e.g., 'ldap://localhost:389' or 'ldaps://localhost:636').
            - bind (dict, optional): Bind parameters with 'dn', 'password', and 'method' (default 'simple').
            - tls (dict): TLS parameters with 'validate' (bool), 'ca_certs_file' (str, required), and 'starttls' (bool, default True).

    Returns:
        dict: A dictionary with 'success' (bool), 'created' (bool), 'error' (str or None), and 'message' (str).
    """
    try:
        if not connection_dict or "url" not in connection_dict:
            return {
                "success": False,
                "created": False,
                "error": "Connection dictionary with 'url' is required",
                "message": "",
            }

        tls_config = connection_dict.get("tls", {})
        if not tls_config or "ca_certs_file" not in tls_config:
            return {
                "success": False,
                "created": False,
                "error": "TLS configuration with 'ca_certs_file' is required",
                "message": "",
            }

        # Ensure starttls defaults to True if not specified
        tls_config.setdefault("starttls", True)
        tls_config.setdefault("validate", True)

        # Ensure bind method defaults to 'simple' if not specified
        bind_config = connection_dict.get("bind", {})
        bind_config.setdefault("method", "simple")

        # Check if connection spec already exists in cache
        if spec_name in _CONNECTION_CACHE:
            return {
                "success": True,
                "created": False,
                "error": None,
                "message": f"Connection spec '{spec_name}' already exists in cache",
            }

        # Prepare the configuration dictionary as a single argument
        config = {"url": connection_dict["url"], "bind": bind_config, "tls": tls_config}

        # Pass the entire configuration as a single dictionary
        conn = __salt__["ldap3.connect"](config)

        if not conn:
            return {
                "success": False,
                "created": False,
                "error": "Failed to establish LDAP connection",
                "message": "",
            }

        # Cache the connection object
        _CONNECTION_CACHE[spec_name] = conn
        log.debug(f"Created and cached LDAP connection spec '{spec_name}'")
        return {
            "success": True,
            "created": True,
            "error": None,
            "message": f"Connection spec '{spec_name}' created and cached",
        }
    except Exception as e:
        return {
            "success": False,
            "created": False,
            "error": f"Failed to create connection spec '{spec_name}': {str(e)}",
            "message": "",
        }


def get_connect_spec(spec_name):
    """
    Retrieve a connection specification from the cache.

    Args:
        spec_name (str): The name of the connection specification.

    Returns:
        dict: A dictionary with 'success' (bool), 'conn' (connection object or None), and 'error' (str or None).
    """
    if spec_name in _CONNECTION_CACHE:
        return {"success": True, "conn": _CONNECTION_CACHE[spec_name], "error": None}
    return {
        "success": False,
        "conn": None,
        "error": f"Connection spec '{spec_name}' not found in cache",
    }


def root_dn_exists(spec_name, root_dn):
    """
    Check if a root DN exists in the LDAP directory using a connection spec.

    Args:
        spec_name (str): The name of the connection specification.
        root_dn (str): The distinguished name to check.

    Returns:
        dict: A dictionary with 'exists' (bool) and 'error' (str or None).
    """
    try:
        conn_result = get_connect_spec(spec_name)
        if not conn_result["success"]:
            return {"exists": False, "error": conn_result["error"]}

        conn = conn_result["conn"]
        result = __salt__["ldap3.search"](
            connection=conn,
            base=root_dn,
            scope="base",
            filter="(objectClass=*)",
            attrs=["dn"],
        )
        if result and len(result) > 0:
            return {"exists": True, "error": None}
        return {"exists": False, "error": None}
    except Exception as e:
        return {"exists": False, "error": f"Failed to check root DN: {str(e)}"}


def create_root_dn(spec_name, root_dn, attributes):
    """
    Create a root DN in the LDAP directory if it doesn't exist using a connection spec.

    Args:
        spec_name (str): The name of the connection specification.
        root_dn (str): The distinguished name to create.
        attributes (dict): Attributes to set for the new DN.

    Returns:
        dict: A dictionary with 'created' (bool), 'error' (str or None), and 'message' (str).
    """
    try:
        conn_result = get_connect_spec(spec_name)
        if not conn_result["success"]:
            return {"created": False, "error": conn_result["error"], "message": ""}

        conn = conn_result["conn"]
        check = root_dn_exists(spec_name, root_dn)
        if check["exists"]:
            return {
                "created": False,
                "error": None,
                "message": f"Root DN {root_dn} already exists",
            }

        __salt__["ldap3.add"](connection=conn, dn=root_dn, attributes=attributes)
        return {
            "created": True,
            "error": None,
            "message": f"Root DN {root_dn} created successfully",
        }
    except Exception as e:
        return {
            "created": False,
            "error": f"Failed to create root DN: {str(e)}",
            "message": "",
        }
