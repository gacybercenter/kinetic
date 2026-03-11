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
            - tls (dict, optional): TLS parameters with 'cacertfile' (str), 'certfile' (str), 'keyfile' (str),
              'starttls' (bool, default False), and 'cert_manager_secret' (str, optional name of k8s secret with certs).
            - admin_bind (dict, optional): Admin bind parameters with 'dn' and 'password' for elevated operations.

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

        # Require TLS configuration
        tls_config = connection_dict.get("tls", {})
        if not tls_config:
            return {
                "success": False,
                "created": False,
                "error": "TLS configuration is required",
                "message": "",
            }

        # Configure TLS options
        if "cacertfile" in tls_config:
            try:
                conn.set_option(ldap.OPT_X_TLS_CACERTFILE, tls_config["cacertfile"])
                conn.set_option(ldap.OPT_X_TLS_NEWCTX, 0)
                log.debug(
                    f"Set TLS CACERTFILE to {tls_config['cacertfile']} for spec '{spec_name}'"
                )
            except AttributeError as e:
                log.warning(f"Could not set TLS CACERTFILE option: {str(e)}")

        # Configure client certificate if provided
        temp_files = None
        if "certfile" in tls_config and "keyfile" in tls_config:
            try:
                conn.set_option(ldap.OPT_X_TLS_CERTFILE, tls_config["certfile"])
                conn.set_option(ldap.OPT_X_TLS_KEYFILE, tls_config["keyfile"])
                conn.set_option(ldap.OPT_X_TLS_NEWCTX, 0)
                log.debug(f"Set TLS client certificate and key for spec '{spec_name}'")
            except AttributeError as e:
                log.warning(f"Could not set TLS client certificate options: {str(e)}")
        elif "cert_manager_secret" in tls_config:
            # Attempt to load certificate data from Kubernetes secret created by cert-manager
            try:
                import kubernetes.client
                from kubernetes import config

                config.load_incluster_config()
                v1 = kubernetes.client.CoreV1Api()
                secret_name = tls_config["cert_manager_secret"]
                namespace = tls_config.get("namespace", "default")
                secret = v1.read_namespaced_secret(secret_name, namespace)
                if "tls.crt" in secret.data and "tls.key" in secret.data:
                    # Write temporary files with cert and key data
                    import os
                    import tempfile

                    cert_fd, cert_path = tempfile.mkstemp(suffix=".crt")
                    key_fd, key_path = tempfile.mkstemp(suffix=".key")
                    temp_files = (cert_path, key_path)
                    try:
                        os.write(cert_fd, base64.b64decode(secret.data["tls.crt"]))
                        os.write(key_fd, base64.b64decode(secret.data["tls.key"]))
                        conn.set_option(ldap.OPT_X_TLS_CERTFILE, cert_path)
                        conn.set_option(ldap.OPT_X_TLS_KEYFILE, key_path)
                        conn.set_option(ldap.OPT_X_TLS_NEWCTX, 0)
                        log.debug(
                            f"Set TLS client certificate from cert-manager secret '{secret_name}' for spec '{spec_name}'"
                        )
                    finally:
                        os.close(cert_fd)
                        os.close(key_fd)
                        # Clean up temporary files immediately after setting options
                        try:
                            if os.path.exists(cert_path):
                                os.remove(cert_path)
                            if os.path.exists(key_path):
                                os.remove(key_path)
                            log.debug(
                                f"Cleaned up temporary TLS files for spec '{spec_name}'"
                            )
                            temp_files = None
                        except Exception as cleanup_e:
                            log.warning(
                                f"Failed to clean up temporary TLS files: {str(cleanup_e)}"
                            )
                else:
                    log.warning(
                        f"Cert-manager secret '{secret_name}' does not contain expected tls.crt and tls.key"
                    )
            except Exception as e:
                log.warning(
                    f"Could not load client certificate from cert-manager secret: {str(e)}"
                )

        # Enable STARTTLS if specified or if using ldap:// protocol with TLS required
        starttls = tls_config.get("starttls", False)
        if starttls or (connection_dict["url"].startswith("ldap://") and tls_config):
            try:
                conn.start_tls_s()
                log.debug(f"Started TLS for spec '{spec_name}'")
            except Exception as e:
                # Clean up any remaining temporary files in case of error
                if temp_files:
                    try:
                        if os.path.exists(temp_files[0]):
                            os.remove(temp_files[0])
                        if os.path.exists(temp_files[1]):
                            os.remove(temp_files[1])
                        log.debug(
                            f"Cleaned up temporary TLS files on error for spec '{spec_name}'"
                        )
                    except Exception as cleanup_e:
                        log.warning(
                            f"Failed to clean up temporary TLS files on error: {str(cleanup_e)}"
                        )
                return {
                    "success": False,
                    "created": False,
                    "error": f"Failed to start TLS for spec '{spec_name}': {str(e)}",
                    "message": "",
                }

        # Perform binding if credentials are provided
        # Check for admin_bind first (for elevated operations like cn=config)
        admin_bind_config = connection_dict.get("admin_bind", {})
        if (
            admin_bind_config
            and "dn" in admin_bind_config
            and "password" in admin_bind_config
        ):
            try:
                method = (
                    ldap.AUTH_SIMPLE
                    if admin_bind_config.get("method", "simple") == "simple"
                    else ldap.AUTH_SIMPLE
                )
                conn.bind_s(
                    admin_bind_config["dn"], admin_bind_config["password"], method
                )
                log.debug(
                    f"Bound to LDAP server as admin {admin_bind_config['dn']} for spec '{spec_name}'"
                )
            except Exception as e:
                # Clean up any remaining temporary files in case of error
                if temp_files:
                    try:
                        if os.path.exists(temp_files[0]):
                            os.remove(temp_files[0])
                        if os.path.exists(temp_files[1]):
                            os.remove(temp_files[1])
                        log.debug(
                            f"Cleaned up temporary TLS files on error for spec '{spec_name}'"
                        )
                    except Exception as cleanup_e:
                        log.warning(
                            f"Failed to clean up temporary TLS files on error: {str(cleanup_e)}"
                        )
                return {
                    "success": False,
                    "created": False,
                    "error": f"Failed to bind as admin to LDAP server for spec '{spec_name}': {str(e)}",
                    "message": "",
                }
        else:
            # Fallback to regular bind if admin_bind is not provided
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
                    # Clean up any remaining temporary files in case of error
                    if temp_files:
                        try:
                            if os.path.exists(temp_files[0]):
                                os.remove(temp_files[0])
                            if os.path.exists(temp_files[1]):
                                os.remove(temp_files[1])
                            log.debug(
                                f"Cleaned up temporary TLS files on error for spec '{spec_name}'"
                            )
                        except Exception as cleanup_e:
                            log.warning(
                                f"Failed to clean up temporary TLS files on error: {str(cleanup_e)}"
                            )
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
        # Ensure temporary files are cleaned up in case of any exception
        if "temp_files" in locals() and temp_files:
            try:
                if os.path.exists(temp_files[0]):
                    os.remove(temp_files[0])
                if os.path.exists(temp_files[1]):
                    os.remove(temp_files[1])
                log.debug(
                    f"Cleaned up temporary TLS files on exception for spec '{spec_name}'"
                )
            except Exception as cleanup_e:
                log.warning(
                    f"Failed to clean up temporary TLS files on exception: {str(cleanup_e)}"
                )
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


def root_dn_exists(spec_name, root_dn, desired_attributes=None):
    """
    Check if a root DN exists in the LDAP directory and optionally if its attributes match the desired state.

    Args:
        spec_name (str): The name of the connection specification.
        root_dn (str): The distinguished name to check.
        desired_attributes (dict, optional): Desired attributes to compare against existing ones.

    Returns:
        dict: A dictionary with 'result' (bool), 'comment' (str), and 'changes' (dict).
    """
    ret = {"result": False, "comment": "", "changes": {}}
    try:
        conn_result = get_connect_spec(spec_name)
        if not conn_result["success"]:
            ret["comment"] = conn_result["error"]
            return ret

        conn = conn_result["conn"]
        # Use SCOPE_BASE to search for the specific DN
        attr_list = (
            ["dn"] + list(desired_attributes.keys()) if desired_attributes else ["dn"]
        )
        result = conn.search_s(
            base=root_dn,
            scope=ldap.SCOPE_SUBTREE,
            filterstr="(objectClass=*)",
            attrlist=attr_list,
        )
        if result and len(result) > 0:
            if not desired_attributes:
                ret["result"] = True
                ret["comment"] = f"Root DN {root_dn} exists."
                return ret

            # Compare current attributes with desired attributes
            current_attrs = result[0][1] if result[0][1] else {}
            matches = True
            for attr, desired_val in desired_attributes.items():
                current_val = current_attrs.get(attr, [])
                # Handle single value vs list
                desired_val_list = (
                    desired_val if isinstance(desired_val, list) else [desired_val]
                )
                # Convert current values to strings for comparison if needed (python-ldap returns bytes)
                current_val_str = [
                    v.decode("utf-8") if isinstance(v, bytes) else v
                    for v in current_val
                ]
                if set(current_val_str) != set(desired_val_list):
                    matches = False
                    log.debug(
                        f"Attribute mismatch for {attr}: current={current_val_str}, desired={desired_val_list}"
                    )
                    break
            ret["result"] = True
            ret["comment"] = f"Root DN {root_dn} exists. Attributes match: {matches}."
            # No changes in exists check, as it's read-only
            return ret
        ret["result"] = (
            True  # Non-existence is a valid result for exists check; use result: True for consistency
        )
        ret["comment"] = f"Root DN {root_dn} does not exist."
        return ret
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to check root DN {root_dn}: {str(e)}"
        return ret


def update_root_dn(spec_name, root_dn, attributes):
    """
    Update attributes of an existing root DN in the LDAP directory.

    Args:
        spec_name (str): The name of the connection specification.
        root_dn (str): The distinguished name to update.
        attributes (dict): Attributes to update on the DN.

    Returns:
        dict: A dictionary with 'result' (bool), 'comment' (str), and 'changes' (dict).
    """
    ret = {"result": False, "comment": "", "changes": {}}
    try:
        conn_result = get_connect_spec(spec_name)
        if not conn_result["success"]:
            ret["comment"] = conn_result["error"]
            return ret

        conn = conn_result["conn"]
        # Fetch current attributes to avoid unnecessary or forbidden updates
        current_attrs_result = root_dn_exists(spec_name, root_dn, attributes)
        if not current_attrs_result["result"] or not current_attrs_result.get(
            "exists", False
        ):  # Check standardized result
            ret["comment"] = f"DN {root_dn} does not exist for update"
            return ret

        current_attrs = {}
        # Fetch all attributes for comparison
        search_result = conn.search_s(
            base=root_dn,
            scope=ldap.SCOPE_BASE,
            filterstr="(objectClass=*)",
            attrlist=list(attributes.keys()),
        )
        if search_result and len(search_result) > 0:
            current_attrs = search_result[0][1] if search_result[0][1] else {}
            # Decode byte strings to compare with desired attributes
            for k in current_attrs:
                current_attrs[k] = [
                    v.decode("utf-8") if isinstance(v, bytes) else v
                    for v in current_attrs[k]
                ]

        # Convert attributes dictionary to list of (attr, value) tuples for modification
        # Ensure all values are lists of byte strings as required by python-ldap
        # Use MOD_ADD for olcModuleLoad to avoid deletion issues
        # Skip updates for olcModulePath if already set
        mod_attrs = []
        changes = {}  # Track changes for standardized return
        for k, v in attributes.items():
            desired_val_list = v if isinstance(v, list) else [v]
            current_val_list = current_attrs.get(k, [])
            if set(desired_val_list) == set(current_val_list):
                continue  # Skip if values are already the same
            changes[k] = {
                "old": current_val_list,
                "new": desired_val_list,
            }  # Record change
            if k == "olcModuleLoad":
                mod_attrs.append(
                    (
                        ldap.MOD_ADD,
                        k,
                        [
                            val.encode("utf-8")
                            if isinstance(val, str)
                            else val.encode("utf-8")
                            for val in desired_val_list
                        ],
                    )
                )
            elif k == "olcModulePath" and current_val_list:
                log.warning(
                    f"Skipping update for {k} on {root_dn} as it cannot be deleted or replaced"
                )
                continue  # Skip update if olcModulePath is already set
            else:
                mod_attrs.append(
                    (
                        ldap.MOD_REPLACE,
                        k,
                        [
                            val.encode("utf-8")
                            if isinstance(val, str)
                            else val.encode("utf-8")
                            for val in desired_val_list
                        ],
                    )
                )

        if not mod_attrs:
            ret["result"] = True
            ret["comment"] = f"No changes needed for {root_dn}"
            return ret

        conn.modify_s(dn=root_dn, modlist=mod_attrs)
        ret["result"] = True
        ret["comment"] = f"Root DN {root_dn} attributes updated successfully"
        ret["changes"] = changes
        return ret
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to update root DN {root_dn}: {str(e)}"
        return ret


def create_root_dn(spec_name, root_dn, attributes=None):
    """
    Create a root DN in the LDAP directory if it doesn't exist or if attributes don't match.
    Returns a dictionary with the result of the operation.

    :param spec_name: Name of the connection specification for LDAP
    :param root_dn: The root DN to create
    :param attributes: Dictionary of attributes for the root DN
    :return: Dictionary with 'result' (bool), 'comment' (str), and 'changes' (dict)
    """
    ret = {"result": False, "comment": "", "changes": {}}
    try:
        conn_result = get_connect_spec(spec_name)
        if not conn_result["success"]:
            ret["comment"] = conn_result["error"]
            return ret

        conn = conn_result["conn"]
        check = root_dn_exists(spec_name, root_dn, attributes)
        if check["result"] and check.get("exists", False):
            if check.get("attributes_match", False):
                ret["result"] = True
                ret["comment"] = (
                    f"Root DN {root_dn} already exists with matching attributes"
                )
                return ret
            else:
                # Update attributes since they differ
                update_result = update_root_dn(spec_name, root_dn, attributes)
                if update_result["result"]:
                    ret["result"] = True
                    ret["comment"] = (
                        f"Root DN {root_dn} exists. {update_result['comment']}"
                    )
                    ret["changes"] = update_result["changes"]
                    return ret
                ret["result"] = False
                ret["comment"] = (
                    f"Failed to update root DN {root_dn}: {update_result['comment']}"
                )
                return ret

        # Create new entry since it doesn't exist
        # Convert attributes dictionary to list of (attr, value) tuples as required by python-ldap
        # Ensure all values are lists of byte strings
        attr_list = [
            (
                k,
                [
                    v.encode("utf-8") if isinstance(v, str) else v.encode("utf-8")
                    for v in (v if isinstance(v, list) else [v])
                ],
            )
            for k, v in attributes.items()
        ]
        conn.add_s(dn=root_dn, modlist=attr_list)
        ret["result"] = True
        ret["comment"] = f"Root DN {root_dn} created successfully"
        ret["changes"] = {"created": root_dn, "attributes": attributes or {}}
        return ret
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to create root DN {root_dn}: {str(e)}"
        return ret


def create_ou(spec_name, ou_dn, attributes):
    """
    Create an OU in the LDAP directory if it doesn't exist, or update it if attributes differ.

    Args:
        spec_name (str): The name of the connection specification.
        ou_dn (str): The distinguished name of the OU to create or update.
        attributes (dict): Attributes to set for the new OU or update on the existing OU.

    Returns:
        dict: A dictionary with 'result' (bool), 'comment' (str), and 'changes' (dict).
    """
    ret = {"result": False, "comment": "", "changes": {}}
    try:
        conn_result = get_connect_spec(spec_name)
        if not conn_result["success"]:
            ret["comment"] = conn_result["error"]
            return ret

        conn = conn_result["conn"]
        check = root_dn_exists(spec_name, ou_dn, attributes)
        if check["exists"]:
            if check["attributes_match"]:
                ret["result"] = True
                ret["comment"] = f"OU {ou_dn} already exists with matching attributes"
                return ret
            else:
                # Update attributes since they differ
                update_result = update_root_dn(spec_name, ou_dn, attributes)
                if update_result["updated"]:
                    ret["result"] = True
                    ret["comment"] = f"OU {ou_dn} exists. {update_result['message']}"
                    ret["changes"] = update_result.get(
                        "changes", {}
                    )  # Pull changes if available from update_root_dn
                    return ret
                ret["result"] = False
                ret["comment"] = (
                    f"Failed to update OU {ou_dn}: {update_result['error']}"
                )
                return ret

        # Create new entry since it doesn't exist
        # Convert attributes dictionary to list of (attr, value) tuples as required by python-ldap
        # Ensure all values are lists of byte strings
        attr_list = [
            (
                k,
                [
                    v.encode("utf-8") if isinstance(v, str) else v.encode("utf-8")
                    for v in (v if isinstance(v, list) else [v])
                ],
            )
            for k, v in attributes.items()
        ]
        conn.add_s(dn=ou_dn, modlist=attr_list)
        ret["result"] = True
        ret["comment"] = f"OU {ou_dn} created successfully"
        ret["changes"] = {"created": ou_dn, "attributes": attributes}
        return ret
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to create OU {ou_dn}: {str(e)}"
        return ret


def create_user(spec_name, user_dn, attributes, password=None):
    """
    Create a user in the LDAP directory if it doesn't exist, or update it if attributes differ.

    Args:
        spec_name (str): The name of the connection specification.
        user_dn (str): The distinguished name of the user to create or update.
        attributes (dict): Attributes to set for the new user or update on the existing user.
        password (str, optional): Password to set for the user, if provided.

    Returns:
        dict: A dictionary with 'result' (bool), 'comment' (str), and 'changes' (dict).
    """
    ret = {"result": False, "comment": "", "changes": {}}
    try:
        conn_result = get_connect_spec(spec_name)
        if not conn_result["success"]:
            ret["comment"] = conn_result["error"]
            return ret

        conn = conn_result["conn"]
        check = root_dn_exists(spec_name, user_dn, attributes)
        if check["exists"]:
            if check["attributes_match"] and not password:
                ret["result"] = True
                ret["comment"] = (
                    f"User {user_dn} already exists with matching attributes"
                )
                return ret
            else:
                # Update attributes or password since they differ or password is provided
                update_attrs = attributes.copy()
                changes = {}  # Track changes
                if password:
                    update_attrs["userPassword"] = password
                    changes["userPassword"] = {
                        "old": "(hidden)",
                        "new": "(set)",
                    }  # Don't log actual password
                update_result = update_root_dn(spec_name, user_dn, update_attrs)
                if update_result["updated"]:
                    ret["result"] = True
                    ret["comment"] = (
                        f"User {user_dn} exists. {update_result['message']}"
                    )
                    ret["changes"] = {**update_result.get("changes", {}), **changes}
                    return ret
                ret["result"] = False
                ret["comment"] = (
                    f"Failed to update user {user_dn}: {update_result['error']}"
                )
                return ret

        # Create new entry since it doesn't exist
        # Convert attributes dictionary to list of (attr, value) tuples as required by python-ldap
        # Ensure all values are lists of byte strings
        create_attrs = attributes.copy()
        changes = {"created": user_dn, "attributes": attributes}
        if password:
            create_attrs["userPassword"] = password
            changes["userPassword"] = "(set)"
        attr_list = [
            (
                k,
                [
                    v.encode("utf-8") if isinstance(v, str) else v.encode("utf-8")
                    for v in (v if isinstance(v, list) else [v])
                ],
            )
            for k, v in create_attrs.items()
        ]
        conn.add_s(dn=user_dn, modlist=attr_list)
        ret["result"] = True
        ret["comment"] = f"User {user_dn} created successfully"
        ret["changes"] = changes
        return ret
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to create user {user_dn}: {str(e)}"
        return ret


def create_group(spec_name, group_dn, attributes, members=None):
    """
    Create a group in the LDAP directory if it doesn't exist, or update it if attributes or members differ.

    Args:
        spec_name (str): The name of the connection specification.
        group_dn (str): The distinguished name of the group to create or update.
        attributes (dict): Attributes to set for the new group or update on the existing group.
        members (list, optional): List of member DNs to set for the group, if provided.

    Returns:
        dict: A dictionary with 'result' (bool), 'comment' (str), and 'changes' (dict).
    """
    ret = {"result": False, "comment": "", "changes": {}}
    try:
        conn_result = get_connect_spec(spec_name)
        if not conn_result["success"]:
            ret["comment"] = conn_result["error"]
            return ret

        conn = conn_result["conn"]
        check_attrs = attributes.copy()
        if members:
            check_attrs["member"] = members
        check = root_dn_exists(spec_name, group_dn, check_attrs)
        if check["exists"]:
            if check["attributes_match"]:
                ret["result"] = True
                ret["comment"] = (
                    f"Group {group_dn} already exists with matching attributes and members"
                )
                return ret
            else:
                # Update attributes or members since they differ
                update_attrs = attributes.copy()
                changes = {}  # Track changes
                if members:
                    update_attrs["member"] = members
                    changes["members"] = {
                        "added": members
                    }  # Simplistic tracking; refine if needed
                update_result = update_root_dn(spec_name, group_dn, update_attrs)
                if update_result["updated"]:
                    ret["result"] = True
                    ret["comment"] = (
                        f"Group {group_dn} exists. {update_result['message']}"
                    )
                    ret["changes"] = {**update_result.get("changes", {}), **changes}
                    return ret
                ret["result"] = False
                ret["comment"] = (
                    f"Failed to update group {group_dn}: {update_result['error']}"
                )
                return ret

        # Create new entry since it doesn't exist
        # Convert attributes dictionary to list of (attr, value) tuples as required by python-ldap
        # Ensure all values are lists of byte strings
        create_attrs = attributes.copy()
        changes = {"created": group_dn, "attributes": attributes}
        if members:
            create_attrs["member"] = members
            changes["members"] = members
        attr_list = [
            (
                k,
                [
                    v.encode("utf-8") if isinstance(v, str) else v.encode("utf-8")
                    for v in (v if isinstance(v, list) else [v])
                ],
            )
            for k, v in create_attrs.items()
        ]
        conn.add_s(dn=group_dn, modlist=attr_list)
        ret["result"] = True
        ret["comment"] = f"Group {group_dn} created successfully"
        ret["changes"] = changes
        return ret
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to create group {group_dn}: {str(e)}"
        return ret


def load_module(spec_name, module_dn, module_info, module_path=None):
    """
    Load a module into OpenLDAP configuration if not already loaded.

    Args:
        spec_name (str): The name of the connection specification.
        module_dn (str): The distinguished name for the module configuration (e.g., 'cn=module{0},cn=config').
        module_info (dict or str): Module information; if str, just the module name; if dict, includes 'name' and other attributes.
        module_path (str, optional): The path to the module directory if needed (e.g., '/opt/bitnami/openldap/lib/openldap').

    Returns:
        dict: A dictionary with 'loaded' (bool), 'updated' (bool), 'error' (str or None), and 'message' (str).
    """
    try:
        conn_result = get_connect_spec(spec_name)
        if not conn_result["success"]:
            return {
                "loaded": False,
                "updated": False,
                "error": conn_result["error"],
                "message": "",
            }

        conn = conn_result["conn"]
        # Handle both string and dictionary format for module_info
        if isinstance(module_info, str):
            module_name = module_info
        else:
            module_name = module_info["name"]

        # Attributes for the module entry
        attributes = {"objectClass": ["olcModuleList"]}
        full_path = "{}/{}".format(module_path, module_name)
        attributes["olcModuleLoad"] = full_path
        if module_path:
            attributes["olcModulePath"] = module_path

        # Check if module entry exists
        check = root_dn_exists(spec_name, module_dn, attributes)
        if check["exists"]:
            log.debug(
                f"Module entry {module_dn} already exists. Treating as success since module replacement requires slapd restart."
            )
            return {
                "loaded": False,
                "updated": False,
                "error": None,
                "message": f"Module entry {module_dn} already exists. No changes made as replacement requires slapd restart.",
            }
        else:
            # Create new module entry since it doesn't exist
            attr_list = [
                (
                    k,
                    [
                        v.encode("utf-8") if isinstance(v, str) else v.encode("utf-8")
                        for v in (v if isinstance(v, list) else [v])
                    ],
                )
                for k, v in attributes.items()
            ]
            conn.add_s(dn=module_dn, modlist=attr_list)
            log.info(f"Module {module_name} loaded successfully at {module_dn}.")
            return {
                "loaded": True,
                "updated": False,
                "error": None,
                "message": f"Module {module_name} loaded successfully at {module_dn}",
            }
    except Exception as e:
        return {
            "loaded": False,
            "updated": False,
            "error": f"Failed to load module {module_name} at {module_dn}: {str(e)}",
            "message": "",
        }
    # finally:
    #     if "conn" in locals() and conn is not None:
    #         try:
    #             log.debug(f"Attempting to unbind connection for module {module_name}")
    #             conn.unbind_s()
    #         except Exception as unbind_error:
    #             log.warning(
    #                 f"Failed to unbind LDAP connection for module {module_name}: {str(unbind_error)}"
    #            )


def configure_overlay(spec_name, database_dn, overlay_name, overlay_index, attributes):
    """
    Configure an overlay for a specific database in the LDAP directory.

    Args:
        spec_name (str): The name of the connection specification.
        database_dn (str): The distinguished name of the database to apply the overlay to (e.g., 'olcDatabase={2}hdb,cn=config').
        overlay_name (str): The name of the overlay (e.g., 'auditlog', 'memberof').
        overlay_index (int or str): The index for the overlay (e.g., 0, to form 'olcOverlay={0}auditlog').
        attributes (dict): Attributes to set for the overlay configuration.

    Returns:
        dict: A dictionary with 'configured' (bool), 'updated' (bool), 'error' (str or None), and 'message' (str).
    """
    try:
        conn_result = get_connect_spec(spec_name)
        if not conn_result["success"]:
            return {
                "configured": False,
                "updated": False,
                "error": conn_result["error"],
                "message": "",
            }

        conn = conn_result["conn"]
        # Construct the DN for the overlay, typically under the database DN
        overlay_dn = f"olcOverlay={{{overlay_index}}}{overlay_name},{database_dn}"

        # Check if overlay exists and attributes match
        check = root_dn_exists(spec_name, overlay_dn, attributes)
        if check["exists"]:
            if check["attributes_match"]:
                return {
                    "configured": False,
                    "updated": False,
                    "error": None,
                    "message": f"Overlay {overlay_dn} already exists with matching attributes",
                }
            else:
                update_result = update_root_dn(spec_name, overlay_dn, attributes)
                if update_result["updated"]:
                    return {
                        "configured": False,
                        "updated": True,
                        "error": None,
                        "message": update_result["message"],
                    }
                return {
                    "configured": False,
                    "updated": False,
                    "error": update_result["error"],
                    "message": "",
                }

        # Create new overlay entry since it doesn't exist
        # Convert attributes dictionary to list of (attr, value) tuples as required by python-ldap
        # Ensure all values are lists of byte strings
        attr_list = [
            (
                k,
                [
                    v.encode("utf-8") if isinstance(v, str) else v.encode("utf-8")
                    for v in (v if isinstance(v, list) else [v])
                ],
            )
            for k, v in attributes.items()
        ]
        conn.add_s(dn=overlay_dn, modlist=attr_list)
        return {
            "configured": True,
            "updated": False,
            "error": None,
            "message": f"Overlay {overlay_dn} configured successfully",
        }
    except Exception as e:
        return {
            "configured": False,
            "updated": False,
            "error": f"Failed to configure overlay {overlay_name} for {database_dn}: {str(e)}",
            "message": "",
        }


def dn_exists(spec_name, dn, desired_attributes=None):
    """
    Check if a DN exists in the LDAP directory and optionally if its attributes match the desired state.

    Args:
        spec_name (str): The name of the connection specification.
        dn (str): The distinguished name to check.
        desired_attributes (dict, optional): Desired attributes to compare against existing ones.

    Returns:
        dict: A dictionary with 'result' (bool), 'comment' (str), and 'changes' (dict).
    """
    ret = {"result": False, "comment": "", "changes": {}}
    try:
        conn_result = get_connect_spec(spec_name)
        if not conn_result["success"]:
            ret["comment"] = conn_result["error"]
            return ret

        conn = conn_result["conn"]

        attr_list = (
            ["dn"] + list(desired_attributes.keys()) if desired_attributes else ["dn"]
        )
        # Split the DN to get the first element (RDN, e.g., 'ou=users' from 'ou=users,dc=example,dc=com')
        dn_parts = dn.split(",", 1)

        result = conn.search_s(
            base=dn,
            scope=ldap.SCOPE_SUBTREE,
            filterstr="(dn_parts[0])",  # Use first element in filterstr
            attrlist=attr_list,
        )
        if result and len(result) > 0:
            if not desired_attributes:
                ret["result"] = True
                ret["comment"] = f"DN {dn} exists."
                return ret

            # Compare current attributes with desired attributes
            current_attrs = result[0][1] if result[0][1] else {}
            matches = True
            for attr, desired_val in desired_attributes.items():
                current_val = current_attrs.get(attr, [])
                # Handle single value vs list
                desired_val_list = (
                    desired_val if isinstance(desired_val, list) else [desired_val]
                )
                # Convert current values to strings for comparison if needed (python-ldap returns bytes)
                current_val_str = [
                    v.decode("utf-8") if isinstance(v, bytes) else v
                    for v in current_val
                ]
                if set(current_val_str) != set(desired_val_list):
                    matches = False
                    log.debug(
                        f"Attribute mismatch for {attr}: current={current_val_str}, desired={desired_val_list}"
                    )
                    break
            ret["result"] = True
            ret["comment"] = f"DN {dn} exists. Attributes match: {matches}."
            # No changes in exists check, as it's read-only
            return ret
        ret["result"] = (
            True  # Non-existence is a valid result for exists check; use result: True for consistency
        )
        ret["comment"] = f"DN {dn} does not exist."
        return ret
    except ldap.NO_SUCH_OBJECT:
        ret["result"] = True
        ret["comment"] = f"DN {dn} does not exist (NO_SUCH_OBJECT)."
        return ret
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to check DN {dn}: {str(e)}"
        return ret
