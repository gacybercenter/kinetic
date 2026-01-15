# -*- coding: utf-8 -*-
"""
Custom SaltStack module for LDAP operations using python-ldap directly
"""

import logging

try:
    import ldap
except ImportError:
    ldap = None

log = logging.getLogger(__name__)

__virtualname__ = "ldap_utils"

# In-memory cache for connection objects during a single Salt run
_CONNECTION_CACHE = {}


def __virtual__():
    """
    Only load if python-ldap library is available
    """
    if ldap is not None:
        return __virtualname__
    return False, "python-ldap library not available"


def create_connect_spec(spec_name, connection_dict):
    """
    Create or update a connection specification for LDAP operations using python-ldap.
    If a connection with the given spec_name already exists in cache, it will not be recreated.

    Args:
        spec_name (str): The name of the connection specification.
        connection_dict (dict): Dictionary with connection parameters:
            - url (str): LDAP server URL (e.g., 'ldap://localhost:389' or 'ldaps://localhost:636').
            - bind (dict, optional): Bind parameters with 'dn', 'password', and 'method' (default 'simple').
            - tls (dict, optional): TLS parameters with 'cacertfile' (str) and 'starttls' (bool, default False).

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

        # Check if connection spec already exists in cache
        if spec_name in _CONNECTION_CACHE:
            return {
                "success": True,
                "created": False,
                "error": None,
                "message": f"Connection spec '{spec_name}' already exists in cache",
            }

        # Initialize LDAP connection with the provided URL
        conn = ldap.initialize(connection_dict["url"])
        if not conn:
            return {
                "success": False,
                "created": False,
                "error": "Failed to initialize LDAP connection",
                "message": "",
            }

        # Configure TLS if provided
        tls_config = connection_dict.get("tls", {})
        if tls_config and "cacertfile" in tls_config:
            try:
                conn.set_option(ldap.OPT_X_TLS_CACERTFILE, tls_config["cacertfile"])
                log.debug(
                    f"Set TLS CACERTFILE to {tls_config['cacertfile']} for spec '{spec_name}'"
                )
            except AttributeError as e:
                log.warning(f"Could not set TLS CACERTFILE option: {str(e)}")

            # Optionally enable STARTTLS if specified
            if tls_config.get("starttls", False):
                try:
                    conn.start_tls_s()
                    log.debug(f"Started TLS for spec '{spec_name}'")
                except Exception as e:
                    return {
                        "success": False,
                        "created": False,
                        "error": f"Failed to start TLS for spec '{spec_name}': {str(e)}",
                        "message": "",
                    }

        # Perform binding if credentials are provided
        bind_config = connection_dict.get("bind", {})
        if bind_config and "dn" in bind_config and "password" in bind_config:
            try:
                method = (
                    ldap.AUTH_SIMPLE
                    if bind_config.get("method", "simple") == "simple"
                    else ldap.AUTH_SIMPLE
                )
                conn.bind_s(bind_config["dn"], bind_config["password"], method)
                log.debug(
                    f"Bound to LDAP server as {bind_config['dn']} for spec '{spec_name}'"
                )
            except Exception as e:
                return {
                    "success": False,
                    "created": False,
                    "error": f"Failed to bind to LDAP server for spec '{spec_name}': {str(e)}",
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
        error_msg = f"Failed to create connection spec '{spec_name}': {str(e)}"
        log.error(error_msg)
        return {
            "success": False,
            "created": False,
            "error": error_msg,
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
        # Use SCOPE_BASE to search for the specific DN
        result = conn.search_s(
            base=root_dn,
            scope=ldap.SCOPE_BASE,
            filterstr="(objectClass=*)",
            attrlist=["dn"],
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

        # Convert attributes dictionary to list of (attr, value) tuples as required by python-ldap
        attr_list = [
            (k, v if isinstance(v, list) else [v]) for k, v in attributes.items()
        ]
        attr_list = [(k, v if isinstance(v, list) else [v]) for k, v in attributes.items()]
        conn.add_s(dn=root_dn, modlist=attr_list)
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
