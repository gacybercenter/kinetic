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
            - tls (dict): TLS parameters with 'cacertfile' (str, required), 'certfile' (str, optional),
              'keyfile' (str, optional), 'cert_manager_secret' (str, optional name of k8s secret with certs),
              'namespace' (str, optional for cert_manager_secret), and 'starttls' (bool, default True).
            - admin_bind (dict, optional): Admin bind parameters with 'dn' and 'password' for elevated operations.

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
    if not tls_config:
        ret["result"] = False
        ret["comment"] = "TLS configuration is required"
        return ret

    # Ensure starttls defaults to True if not specified and protocol is ldap://
    if "starttls" not in tls_config and connection_dict["url"].startswith("ldap://"):
        connection_dict["tls"]["starttls"] = True

    # Ensure bind method defaults to 'simple' if not specified
    bind_config = connection_dict.get("bind", {})
    if bind_config and "method" not in bind_config:
        bind_config["method"] = "simple"
        connection_dict["bind"] = bind_config

    admin_bind_config = connection_dict.get("admin_bind", {})
    if admin_bind_config and "method" not in admin_bind_config:
        admin_bind_config["method"] = "simple"
        connection_dict["admin_bind"] = admin_bind_config

    # Validate client certificate configuration if provided
    if "cert_manager_secret" in tls_config:
        if "namespace" not in tls_config:
            tls_config["namespace"] = "default"
            connection_dict["tls"] = tls_config
    elif "certfile" in tls_config or "keyfile" in tls_config:
        if not ("certfile" in tls_config and "keyfile" in tls_config):
            ret["result"] = False
            ret["comment"] = (
                "Both 'certfile' and 'keyfile' must be provided for client certificate configuration"
            )
            return ret

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


def ou_present(name, spec_name, base_dn, ous=None):
    """
    Ensure that Organizational Units (OUs) exist in the LDAP directory based on pillar data.

    Args:
        name (str): The name of the state (used for identification in Salt).
        spec_name (str): The name of the connection specification to use.
        base_dn (str): The base distinguished name under which OUs will be created (e.g., 'dc=rsc,dc=gacyberrange,dc=org').
        ous (list, optional): List of OU definitions with 'name' and 'dc'. If not provided, fetched from pillar['ldap']['orgunits'].

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

    # Fetch OUs from pillar if not provided
    if ous is None:
        ous = __pillar__.get("ldap", {}).get("orgunits", [])

    if not ous:
        ret["comment"] = "No organizational units defined in pillar or parameters."
        return ret

    changes = []
    for ou in ous:
        if "name" not in ou or "dc" not in ou:
            ret["result"] = False
            ret["comment"] = f"Invalid OU definition missing 'name' or 'dc': {ou}"
            return ret

        # Construct OU DN, e.g., 'ou=users,dc=rsc,dc=gacyberrange,dc=org'
        ou_dn = f"ou={ou['name']},{base_dn}"
        attributes = {"objectClass": ["organizationalUnit"], "ou": ou["name"]}

        # Check if OU exists and attributes match
        check_result = __salt__["ldap_utils.root_dn_exists"](
            spec_name, ou_dn, attributes
        )
        if check_result["exists"] and check_result["attributes_match"]:
            log.debug(f"OU {ou_dn} already exists with matching attributes.")
            continue

        if check_result["error"]:
            ret["result"] = False
            ret["comment"] = f"Error checking OU {ou_dn}: {check_result['error']}"
            return ret

        # If in test mode, report what would be done
        if __opts__["test"]:
            ret["result"] = None
            ret["comment"] = (
                f"Would {'update' if check_result['exists'] else 'create'} OU {ou_dn}."
            )
            ret["changes"][ou_dn] = {
                "would_action": "update" if check_result["exists"] else "create"
            }
            return ret

        # Create or update the OU
        create_result = __salt__["ldap_utils.create_ou"](spec_name, ou_dn, attributes)
        if create_result["created"]:
            changes.append({"ou": ou_dn, "action": "created"})
            log.info(f"Created OU {ou_dn}")
        elif create_result["updated"]:
            changes.append({"ou": ou_dn, "action": "updated"})
            log.info(f"Updated OU {ou_dn}")
        else:
            ret["result"] = False
            ret["comment"] = (
                f"Failed to {'update' if check_result['exists'] else 'create'} OU {ou_dn}: {create_result['error']}"
            )
            return ret

    if changes:
        ret["changes"] = {"ous": changes}
        ret["comment"] = f"Processed {len(changes)} OU(s) successfully."
    else:
        ret["comment"] = "All OUs already exist with matching attributes."

    return ret


def user_present(name, spec_name, base_dn, users=None):
    """
    Ensure that users exist in the LDAP directory based on pillar data.

    Args:
        name (str): The name of the state (used for identification in Salt).
        spec_name (str): The name of the connection specification to use.
        base_dn (str): The base distinguished name under which users will be created (e.g., 'ou=users,dc=rsc,dc=gacyberrange,dc=org').
        users (list, optional): List of user definitions with 'name', 'sn', 'uid', and 'pass'. If not provided, fetched from pillar['ldap']['users'].

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

    # Fetch users from pillar if not provided
    if users is None:
        users = __pillar__.get("ldap", {}).get("users", [])

    if not users:
        ret["comment"] = "No users defined in pillar or parameters."
        return ret

    changes = []
    for user in users:
        if "name" not in user or "sn" not in user or "uid" not in user:
            ret["result"] = False
            ret["comment"] = (
                f"Invalid user definition missing 'name', 'sn', or 'uid': {user}"
            )
            return ret

        # Construct user DN, e.g., 'uid=mdanielson,ou=users,dc=rsc,dc=gacyberrange,dc=org'
        user_dn = f"uid={user['uid']},{base_dn}"
        attributes = {
            "objectClass": ["person", "organizationalPerson", "inetOrgPerson"],
            "cn": user["name"],
            "sn": user["sn"],
            "uid": user["uid"],
        }

        # Check if user exists and attributes match
        check_result = __salt__["ldap_utils.root_dn_exists"](
            spec_name, user_dn, attributes
        )
        if (
            check_result["exists"]
            and check_result["attributes_match"]
            and "pass" not in user
        ):
            log.debug(f"User {user_dn} already exists with matching attributes.")
            continue
        elif (
            check_result["exists"]
            and check_result["attributes_match"]
            and "pass" in user
        ):
            log.warning(
                f"User {user_dn} exists with matching attributes, skipping password update as per policy."
            )
            continue
        if check_result["error"]:
            ret["result"] = False
            ret["comment"] = f"Error checking user {user_dn}: {check_result['error']}"
            return ret

        # If in test mode, report what would be done
        if __opts__["test"]:
            ret["result"] = None
            ret["comment"] = (
                f"Would {'update' if check_result['exists'] else 'create'} user {user_dn}."
            )
            ret["changes"][user_dn] = {
                "would_action": "update" if check_result["exists"] else "create"
            }
            return ret

        # Create or update the user
        password = user.get("pass", "")
        create_result = __salt__["ldap_utils.create_user"](
            spec_name, user_dn, attributes, password
        )
        if create_result["created"]:
            changes.append({"user": user_dn, "action": "created"})
            log.info(f"Created user {user_dn}")
        elif create_result["updated"]:
            changes.append({"user": user_dn, "action": "updated"})
            log.info(f"Updated user {user_dn}")
        else:
            ret["result"] = False
            ret["comment"] = (
                f"Failed to {'update' if check_result['exists'] else 'create'} user {user_dn}: {create_result.get('error', 'Unknown error')}"
            )
            return ret

    if changes:
        ret["changes"] = {"users": changes}
        ret["comment"] = f"Processed {len(changes)} user(s) successfully."
    else:
        ret["comment"] = "All users already exist with matching attributes."

    return ret


def group_present(name, spec_name, base_dn, groups=None):
    """
    Ensure that groups exist in the LDAP directory based on pillar data.

    Args:
        name (str): The name of the state (used for identification in Salt).
        spec_name (str): The name of the connection specification to use.
        base_dn (str): The base distinguished name under which groups will be created (e.g., 'ou=groups,dc=rsc,dc=gacyberrange,dc=org').
        groups (list, optional): List of group definitions with 'name' and 'members'. If not provided, fetched from pillar['ldap']['groups'].

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

    # Fetch groups from pillar if not provided
    if groups is None:
        groups = __pillar__.get("ldap", {}).get("groups", [])

    if not groups:
        ret["comment"] = "No groups defined in pillar or parameters."
        return ret

    changes = []
    for group in groups:
        if "name" not in group:
            ret["result"] = False
            ret["comment"] = f"Invalid group definition missing 'name': {group}"
            return ret

        # Construct group DN, e.g., 'cn=admins,ou=groups,dc=rsc,dc=gacyberrange,dc=org'
        group_dn = f"cn={group['name']},{base_dn}"
        attributes = {"objectClass": ["groupOfNames"], "cn": group["name"]}
        # Construct member DNs if members are provided
        members = []
        if "members" in group and group["members"]:
            # Assume members are uids under ou=users, adjust base DN accordingly
            members = [
                f"uid={member},ou=users,{base_dn.split('ou=groups,')[1]}"
                for member in group["members"]
            ]

        # Check if group exists and attributes/members match
        check_attrs = attributes.copy()
        if members:
            check_attrs["member"] = members
        check_result = __salt__["ldap_utils.root_dn_exists"](
            spec_name, group_dn, check_attrs
        )
        if check_result["exists"] and check_result["attributes_match"]:
            log.debug(
                f"Group {group_dn} already exists with matching attributes and members."
            )
            continue

        if check_result["error"]:
            ret["result"] = False
            ret["comment"] = f"Error checking group {group_dn}: {check_result['error']}"
            return ret

        # If in test mode, report what would be done
        if __opts__["test"]:
            ret["result"] = None
            ret["comment"] = (
                f"Would {'update' if check_result['exists'] else 'create'} group {group_dn}."
            )
            ret["changes"][group_dn] = {
                "would_action": "update" if check_result["exists"] else "create"
            }
            return ret

        # Create or update the group
        create_result = __salt__["ldap_utils.create_group"](
            spec_name, group_dn, attributes, members if members else None
        )
        if create_result["created"]:
            changes.append({"group": group_dn, "action": "created"})
            log.info(f"Created group {group_dn}")
        elif create_result["updated"]:
            changes.append({"group": group_dn, "action": "updated"})
            log.info(f"Updated group {group_dn}")
        else:
            ret["result"] = False
            ret["comment"] = (
                f"Failed to {'update' if check_result['exists'] else 'create'} group {group_dn}: {create_result['error']}"
            )
            return ret

    if changes:
        ret["changes"] = {"groups": changes}
        ret["comment"] = f"Processed {len(changes)} group(s) successfully."
    else:
        ret["comment"] = "All groups already exist with matching attributes."

    return ret


def module_present(
    name,
    spec_name,
    module_base_dn,
    modules=None,
    module_path=None,
    connection_dict=None,
):
    """
    Ensure that specified modules are loaded into OpenLDAP configuration.

    Args:
        name (str): The name of the state (used for identification in Salt).
        spec_name (str): The name of the connection specification to use.
        module_base_dn (str): The base distinguished name for module configuration (e.g., 'cn=module{0},cn=config').
        modules (list, optional): List of module names or dicts with additional info. If not provided, fetched from pillar['ldap']['modules'].
        module_path (str, optional): Path to the module directory if needed (e.g., '/opt/bitnami/openldap/lib/openldap').
        connection_dict (dict, optional): Connection dictionary to use, if not provided, constructed from pillar with admin credentials.

    Returns:
        dict: A dictionary containing the state result.
    """
    ret = {"name": name, "result": True, "changes": {}, "comment": ""}

    # Check if connection spec exists
    conn_result = __salt__["ldap_utils.get_connect_spec"](spec_name)
    if not conn_result["success"]:
        # If connection spec doesn't exist, attempt to create it with admin credentials
        if connection_dict is None:
            connection_dict = __pillar__.get("ldap", {}).get("connection", {})
            admin_user = __pillar__.get("ldap", {}).get("admin-user", {})
            if admin_user and "name" in admin_user and "password" in admin_user:
                connection_dict["admin_bind"] = {
                    "dn": f"cn={admin_user['name']},cn=config",
                    "password": admin_user["password"],
                    "method": "simple",
                }
            # Ensure url is defined with a fallback if not present or empty
            if "url" not in connection_dict or not connection_dict["url"]:
                connection_dict["url"] = __pillar__.get("ldap", {}).get(
                    "url", "ldap://localhost:389"
                )
                log.warning(
                    f"URL not found or empty in connection dictionary for spec '{spec_name}', using fallback URL: {connection_dict['url']}"
                )

        # Create the connection spec if it doesn't exist
        create_result = __salt__["ldap_utils.create_connect_spec"](
            spec_name, connection_dict
        )
        if not create_result["success"]:
            ret["result"] = False
            ret["comment"] = (
                f"Failed to create connection spec '{spec_name}': {create_result['error']}"
            )
            return ret

    # Fetch modules and module_path from pillar if not provided
    if modules is None:
        modules = __pillar__.get("ldap", {}).get("modules", [])
    if module_path is None:
        module_path = __pillar__.get("ldap", {}).get(
            "modulePath", "/opt/bitnami/openldap/lib/openldap"
        )

    if not modules:
        ret["comment"] = "No modules defined in pillar or parameters."
        return ret

    changes = []
    for module_entry in modules:
        # Handle both string and dictionary format for module_entry
        if isinstance(module_entry, str):
            module_info = module_entry
        else:
            module_info = module_entry

        # If in test mode, report what would be done
        if __opts__["test"]:
            ret["result"] = None
            ret["comment"] = (
                f"Would load module from {module_info} at {module_base_dn}."
            )
            ret["changes"][str(module_info)] = {"would_load": module_base_dn}
            return ret

        # Load the module
        load_result = __salt__["ldap_utils.load_module"](
            spec_name, module_base_dn, module_info, module_path
        )
        if load_result["loaded"]:
            changes.append(
                {"module": str(module_info), "action": "loaded", "dn": module_base_dn}
            )
            log.info(f"Loaded module from {module_info} at {module_base_dn}")
        elif load_result["updated"]:
            changes.append(
                {"module": str(module_info), "action": "updated", "dn": module_base_dn}
            )
            log.info(
                f"Updated module configuration for {module_info} at {module_base_dn}"
            )
        elif load_result["error"]:
            ret["result"] = False
            ret["comment"] = (
                f"Failed to load module {module_info}: {load_result['error']}"
            )
            return ret

    if changes:
        ret["changes"] = {"modules": changes}
        ret["comment"] = f"Processed {len(changes)} module(s) successfully."
    else:
        ret["comment"] = "All modules already loaded with matching configuration."

    return ret


def overlay_present(name, spec_name, database_dn, overlays=None, connection_dict=None):
    """
    Ensure that specified overlays are configured for a specific database in the LDAP directory.

    Args:
        name (str): The name of the state (used for identification in Salt).
        spec_name (str): The name of the connection specification to use.
        database_dn (str): The distinguished name of the database to apply overlays to (e.g., 'olcDatabase={2}hdb,cn=config').
        overlays (list, optional): List of overlay configurations with 'name', 'index', and 'attributes'. If not provided, constructed from pillar['ldap']['modules'].
        connection_dict (dict, optional): Connection dictionary to use, if not provided, constructed from pillar with admin credentials.

    Returns:
        dict: A dictionary containing the state result.
    """
    ret = {"name": name, "result": True, "changes": {}, "comment": ""}

    # Check if connection spec exists or create with admin credentials
    if connection_dict is None:
        connection_dict = __pillar__.get("ldap", {}).get("connection", {})
        admin_user = __pillar__.get("ldap", {}).get("admin-user", {})
        if admin_user and "name" in admin_user and "password" in admin_user:
            connection_dict["admin_bind"] = {
                "dn": f"cn={admin_user['name']},cn=config",
                "password": admin_user["password"],
                "method": "simple",
            }

            # Ensure url is defined with a fallback if not present or empty
            if "url" not in connection_dict or not connection_dict["url"]:
                connection_dict["url"] = __pillar__.get("ldap", {}).get(
                    "url", "ldap://localhost:389"
                )
                log.warning(
                    f"URL not found or empty in connection dictionary for spec '{spec_name}', using fallback URL: {connection_dict['url']}"
                )

    # Ensure connection spec is created with admin credentials
    conn_result = __salt__["ldap_utils.create_connect_spec"](spec_name, connection_dict)
    if not conn_result["success"]:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to create connection spec '{spec_name}': {conn_result['error']}"
        )
        return ret

    # Fetch overlays from pillar['ldap']['modules'] if not provided
    if overlays is None:
        overlays = []
        modules = __pillar__.get("ldap", {}).get("modules", [])
        for module_entry in modules:
            if isinstance(module_entry, dict):
                module_name = list(module_entry.keys())[0]
                module_data = module_entry[module_name]
                if "overlay" in module_data:
                    overlay_config = {
                        "name": module_data["overlay"],
                        "index": len(
                            overlays
                        ),  # Simple incremental index, can be adjusted
                        "attributes": {
                            "objectClass": [
                                module_data.get("objectClass", "olcOverlayConfig")
                            ],
                            "olcOverlay": module_data["overlay"],
                        },
                    }
                    # Add specific attributes for certain overlays, e.g., logfile for auditlog
                    if module_data["overlay"] == "auditlog":
                        logfile = __pillar__.get("ldap", {}).get(
                            "logfile", "/audit.log"
                        )
                        overlay_config["attributes"]["olcAuditLogFile"] = logfile
                    overlays.append(overlay_config)

    if not overlays:
        ret["comment"] = "No overlays defined in pillar or parameters."
        return ret

    changes = []
    for overlay in overlays:
        if (
            "name" not in overlay
            or "index" not in overlay
            or "attributes" not in overlay
        ):
            ret["result"] = False
            ret["comment"] = (
                f"Invalid overlay definition missing required fields: {overlay}"
            )
            return ret

        overlay_name = overlay["name"]
        overlay_index = overlay["index"]
        attributes = overlay["attributes"]

        # If in test mode, report what would be done
        if __opts__["test"]:
            ret["result"] = None
            ret["comment"] = (
                f"Would configure overlay {overlay_name} for {database_dn}."
            )
            ret["changes"][overlay_name] = {
                "would_configure": database_dn,
                "index": overlay_index,
            }
            return ret

        # Configure the overlay
        config_result = __salt__["ldap_utils.configure_overlay"](
            spec_name, database_dn, overlay_name, overlay_index, attributes
        )
        if config_result["configured"]:
            changes.append(
                {"overlay": overlay_name, "action": "configured", "dn": database_dn}
            )
            log.info(f"Configured overlay {overlay_name} for {database_dn}")
        elif config_result["updated"]:
            changes.append(
                {"overlay": overlay_name, "action": "updated", "dn": database_dn}
            )
            log.info(f"Updated overlay {overlay_name} for {database_dn}")
        elif config_result["error"]:
            ret["result"] = False
            ret["comment"] = (
                f"Failed to configure overlay {overlay_name}: {config_result['error']}"
            )
            return ret

    if changes:
        ret["changes"] = {"overlays": changes}
        ret["comment"] = f"Processed {len(changes)} overlay(s) successfully."
    else:
        ret["comment"] = "All overlays already configured with matching attributes."

    return ret
