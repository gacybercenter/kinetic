# -*- coding: utf-8 -*-
"""
Custom SaltStack state for ensuring LDAP connection specs and root DN presence
"""

import logging

log = logging.getLogger(__name__)

__virtualname__ = "ldap"


def __virtual__():
    """
    Only load if ldap_utils module is available
    """
    if "ldap_utils.create_connect_spec" in __salt__:
        return __virtualname__
    return False, "ldap_utils module not available"


def connect_spec_present(name, spec_name, connection_dict):
    """
    Ensure that an LDAP connection specification is created and cached.

    Args:
        name (str): The name of the state (used for identification in Salt).
        spec_name (str): The name of the connection specification to cache.
        connection_dict (dict): Dictionary with connection parameters (required):
            - url (str): LDAP server URL (e.g., 'ldap://localhost:389' or 'ldaps://localhost:636').
            - bind (dict, optional): Bind parameters with 'dn', 'password', and 'method' (default 'simple').
            - tls (dict): TLS parameters with 'validate' (bool), 'ca_certs_file' (str, required), and 'starttls' (bool, default True).

    Returns:
        dict: A dictionary containing the state result.
    """
    ret = {"name": name, "result": True, "changes": {}, "comment": ""}

    # Validate that connection_dict and required fields are provided
    if not connection_dict or "url" not in connection_dict:
        ret["result"] = False
        ret["comment"] = "Connection dictionary with 'url' is required"
        return ret

    tls_config = connection_dict.get("tls", {})
    if not tls_config or "cacertfile" not in tls_config:
        ret["result"] = False
        ret["comment"] = "TLS configuration with 'ca_certs_file' is required"
        return ret

    # Ensure starttls defaults to True if not specified
    if "starttls" not in tls_config:
        connection_dict["tls"]["starttls"] = True

    # Ensure bind method defaults to 'simple' if not specified
    bind_config = connection_dict.get("bind", {})
    if "method" not in bind_config:
        bind_config["method"] = "simple"
    connection_dict["bind"] = bind_config

    # Check if connection spec already exists
    conn_result = __salt__["ldap_utils.get_connect_spec"](spec_name)
    if conn_result["success"]:
        ret["comment"] = f"Connection spec '{spec_name}' already exists."
        return ret

    # If in test mode, report what would be done
    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = f"Would create connection spec '{spec_name}'."
        ret["changes"] = {"connect_spec": {"would_create": spec_name}}
        return ret

    # Create the connection spec
    create_result = __salt__["ldap_utils.create_connect_spec"](
        spec_name, connection_dict
    )
    if create_result["success"]:
        if create_result["created"]:
            ret["changes"] = {"connect_spec": {"created": spec_name}}
            ret["comment"] = create_result["message"]
        else:
            ret["comment"] = create_result["message"]
    else:
        ret["result"] = False
        ret["comment"] = create_result["error"]

    return ret


def root_dn_present(name, spec_name, root_dn, attributes=None):
    """
    Ensure that a root DN exists in the LDAP directory with the specified attributes.

    Args:
        name (str): The name of the state (used for identification in Salt).
        spec_name (str): The name of the connection specification to use.
        root_dn (str): The distinguished name to ensure exists.
        attributes (dict, optional): Attributes to set or update on the DN. Defaults to None.

    Returns:
        dict: A dictionary containing the state result.
    """
    ret = {"name": name, "result": True, "changes": {}, "comment": ""}

    # Check if connection spec exists
    conn_result = __salt__["ldap_utils.get_connect_spec"](spec_name)
    if not conn_result["success"]:
        ret["result"] = False
        ret["comment"] = (
            f"Connection spec '{spec_name}' not found: {conn_result['error']}"
        )
        return ret

    # Check if root DN exists and attributes match
    check_result = __salt__["ldap_utils.root_dn_exists"](
        spec_name, root_dn, attributes or {}
    )
    if check_result["exists"] and check_result["attributes_match"]:
        ret["comment"] = f"Root DN {root_dn} already exists with matching attributes."
        return ret

    if check_result["error"]:
        ret["result"] = False
        ret["comment"] = check_result["error"]
        return ret

    # If in test mode, report what would be done
    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = (
            f"Would {'update' if check_result['exists'] else 'create'} root DN {root_dn}."
        )
        ret["changes"] = {
            "root_dn": {
                "would_action": "update" if check_result["exists"] else "create",
                "dn": root_dn,
            }
        }
        return ret

    # Create or update the root DN
    create_result = __salt__["ldap_utils.create_root_dn"](
        spec_name, root_dn, attributes or {}
    )
    if create_result["created"]:
        ret["changes"] = {"root_dn": {"created": root_dn}}
        ret["comment"] = create_result["message"]
    elif create_result["updated"]:
        ret["changes"] = {"root_dn": {"updated": root_dn}}
        ret["comment"] = create_result["message"]
    else:
        ret["result"] = False
        ret["comment"] = create_result["error"] or create_result["message"]

    return ret
