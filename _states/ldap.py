# -*- coding: utf-8 -*-
"""
Custom SaltStack state for ensuring LDAP connection specs and root DN presence
"""

import logging
import re

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


def root_dn_present(name, root_dn, spec_name, attributes=None, **kwargs):
    """
    Ensure that the specified root DN exists in the LDAP directory.

    :param name: The name of the state (for SaltStack identification)
    :param root_dn: The root DN to ensure exists
    :param spec_name: Name of the connection specification for LDAP
    :param attributes: Dictionary of attributes for the root DN
    :return: Dictionary with 'result' (bool), 'comment' (str), 'changes' (dict), and 'name' (str)
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    # Check if root DN exists, handling potential errors
    exists_check = __salt__["ldap_utils.root_dn_exists"](spec_name, root_dn)
    exists = False
    if (
        isinstance(exists_check, dict)
        and "result" in exists_check
        and exists_check["result"]
    ):
        exists = True

    if exists:
        # Root DN exists, check if attributes need updating
        update_result = __salt__["ldap_utils.update_root_dn"](
            spec_name, root_dn, attributes or {}
        )
        if isinstance(update_result, dict):
            if update_result.get("updated", False) or update_result.get(
                "result", False
            ):
                ret["result"] = True
                ret["comment"] = f"Root DN {root_dn} exists, attributes updated."
                ret["changes"] = update_result.get("changes", {})
            elif (
                update_result.get("changes")
                and len(update_result.get("changes", {})) > 0
            ):
                ret["result"] = True
                ret["comment"] = f"Root DN {root_dn} exists, attributes updated."
                ret["changes"] = update_result.get("changes", {})
            else:
                ret["result"] = True
                ret["comment"] = (
                    f"Root DN {root_dn} already exists with matching attributes."
                )
        else:
            ret["result"] = True
            ret["comment"] = (
                f"Root DN {root_dn} already exists with matching attributes."
            )
        return ret
    else:
        # Root DN does not exist or check failed, attempt creation
        create_result = __salt__["ldap_utils.create_root_dn"](
            spec_name, root_dn, attributes or {}
        )
        if isinstance(create_result, dict):
            if (
                create_result.get("created", False)
                or create_result.get("updated", False)
                or create_result.get("result", False)
            ):
                ret["result"] = True
                ret["comment"] = create_result.get(
                    "message", f"Root DN {root_dn} created successfully."
                )
                ret["changes"] = create_result.get("changes", {})
            elif "desc" in create_result and create_result["desc"] == "Already exists":
                ret["result"] = True
                ret["comment"] = (
                    f"Root DN {root_dn} already exists (detected during creation attempt)."
                )
            else:
                ret["result"] = False
                ret["comment"] = (
                    f"Failed to create root DN {root_dn}: {create_result.get('message', str(create_result))}"
                )
        return ret


def ou_present(name, spec_name, base_dn=None, ous=None):
    """
    Ensure that Organizational Units (OUs) exist in the LDAP directory based on pillar data or provided parameters.

    Args:
        name (str): The name of the state (used for identification in Salt). If ous is None, this is treated as the OU DN.
        spec_name (str): The name of the connection specification to use.
        base_dn (str, optional): The base distinguished name under which OUs will be created (e.g., 'dc=rsc,dc=gacyberrange,dc=org').
        ous (list, optional): List of OU definitions with 'name' and 'dc'. If not provided and name is a DN, treats as single OU.

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

    # If ous is not provided, treat as single OU using the name as ou_dn
    if ous is None:
        ou_dn = name  # Assume name is the full OU DN
        # Extract ou name from DN for attributes (e.g., ou=users from ou=users,dc=...)
        ou_name_match = re.match(r"ou=([^,]+)", ou_dn)
        if not ou_name_match:
            ret["result"] = False
            ret["comment"] = f"Invalid OU DN format: {ou_dn}"
            return ret
        ou_name = ou_name_match.group(1)
        ous = [
            {"name": ou_name}
        ]  # Create single-item list; 'dc' not required in single mode

    # Fetch OUs from pillar if ous is empty list
    if not ous:
        ous = __pillar__.get("ldap", {}).get("orgunits", [])

    if not ous:
        ret["comment"] = "No organizational units defined in pillar or parameters."
        return ret

    all_success = True
    changes = []
    comments = []
    for ou in ous:
        if "name" not in ou:
            all_success = False
            comments.append(f"Invalid OU definition missing 'name': {ou}")
            continue

        # Construct OU DN, e.g., 'ou=users,dc=rsc,dc=gacyberrange,dc=org'
        ou_dn = f"ou={ou['name']},{base_dn or ''}"
        attributes = {"objectClass": ["organizationalUnit"], "ou": ou["name"]}

        check_result = __salt__["ldap_utils.dn_exists"](spec_name, ou_dn, attributes)

        # Use explicit keys from check_result
        exists = check_result.get("exists", False)
        attributes_match = check_result.get("attributes_match", False)
        # Handle the case where result is False due to "No such object" - this means it doesn't exist, not an error
        if not check_result["result"] and "No such object" in check_result["comment"]:
            exists = False
            attributes_match = False
        elif not check_result["result"]:
            all_success = False
            comments.append(f"Error checking OU {ou_dn}: {check_result['comment']}")
            continue
        else:
            # If result is True, infer existence and match from comment if explicit keys are missing
            exists = exists or "exists" in check_result["comment"].lower()
            attributes_match = (
                attributes_match
                or "matching attributes" in check_result["comment"].lower()
            )

        if exists and attributes_match:
            log.debug(f"OU {ou_dn} already exists with matching attributes.")
            continue

        # If in test mode, report what would be done
        if __opts__["test"]:
            ret["result"] = None
            comments.append(f"Would {'update' if exists else 'create'} OU {ou_dn}.")
            ret["changes"][ou_dn] = {"would_action": "update" if exists else "create"}
            continue  # Continue to next OU in test mode

        # Create or update the OU
        create_result = __salt__["ldap_utils.create_ou"](spec_name, ou_dn, attributes)
        if isinstance(create_result, dict):
            if create_result.get("result", False):
                action = (
                    "updated"
                    if "updated" in create_result.get("comment", "").lower()
                    else "created"
                )
                changes.append(
                    {
                        "ou": ou_dn,
                        "action": action,
                        "details": create_result.get("changes", {}),
                    }
                )
                log.info(f"{action.capitalize()} OU {ou_dn}")
                continue
            else:
                comment = create_result.get("comment", "")
                if (
                    "exists" in comment.lower()
                    or "updated" in comment.lower()
                    or "matching attributes" in comment.lower()
                ):
                    changes.append({"ou": ou_dn, "action": "exists/updated"})
                    log.info(f"OU {ou_dn} already exists or updated")
                    continue
                all_success = False
                comments.append(
                    f"Failed to {'update' if exists else 'create'} OU {ou_dn}: {comment}"
                )
        else:
            all_success = False
            comments.append(
                f"Unexpected response from create_ou for {ou_dn}: {str(create_result)}"
            )
        continue

    if changes:
        ret["changes"] = {"ous": changes}
    if comments:
        ret["comment"] = " | ".join(comments)
    else:
        ret["comment"] = "All OUs already exist with matching attributes."

    ret["result"] = all_success
    return ret


def user_present(name, spec_name, base_dn, uid, cn, sn, description, password=None):
    """
    Ensure that a single user exists in the LDAP directory, creating or updating as needed.

    Args:
        name (str): The name of the state (used for identification in Salt).
        spec_name (str): The name of the connection specification to use.
        base_dn (str): The base distinguished name under which the user will be created/updated (e.g., 'ou=users,dc=rsc,dc=gacyberrange,dc=org').
        uid (str): The user ID to set.
        cn (str): The common name (CN) of the user.
        sn (str): The surname (sn) to set.
        description (str): The description to set.
        password (str, optional): Password to set for the user (only on creation).

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

    # Construct user DN, e.g., 'cn=cn,base_dn'
    user_dn = f"cn={cn},{base_dn}"

    # Prepare attributes for existence check (mirroring fixed attributes in create_user/update_user)
    attributes = {
        "objectClass": [
            "person",
            "organizationalPerson",
            "inetOrgPerson",
            "posixAccount",
        ],
        "uid": uid,
        "cn": cn,
        "sn": sn,
        "description": description,
        "uidNumber": "0",  # Default value, can be overridden if needed
        "gidNumber": "0",  # Default value, can be overridden if needed
        "homeDirectory": f"/home/{uid}",
        "loginShell": "/bin/bash",
    }

    # Check if group exists and attributes match
    if "ldap_utils.dn_exists" not in __salt__:
        ret["result"] = False
        ret["comment"] = (
            "ldap_utils.dn_exists function not found. Please ensure the module is synced to the minion with 'saltutil.sync_modules'."
        )
        return ret
    check_result = __salt__["ldap_utils.dn_exists"](spec_name, user_dn, attributes)
    if not check_result["result"]:
        if "No such object" in check_result["comment"]:
            exists = False
            attributes_match = False
        else:
            ret["result"] = False
            ret["comment"] = f"Error checking user {user_dn}: {check_result['comment']}"
            return ret
    else:
        exists = check_result.get("exists", False)
        attributes_match = check_result.get("attributes_match", False)

    # Password is only ever set on creation, never on update - if the user
    # already exists, its password is left untouched regardless of what is
    # provided in pillar, so it has no bearing on whether anything changed.
    if exists and attributes_match:
        ret["comment"] = f"User {user_dn} already exists with matching attributes."
        return ret

    # If in test mode, report what would be done
    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = f"Would {'update' if exists else 'create'} user {user_dn}."
        ret["changes"][user_dn] = {"would_action": "update" if exists else "create"}
        return ret

    # Create or update based on existence
    if not exists:
        # Call create_user
        create_result = __salt__["ldap_utils.create_user"](
            spec_name,
            user_dn,
            uid,
            cn,
            sn,
            description,
            password,
            uid_number=None,
            gid_number=None,
            home_directory=None,
            login_shell=None,
        )
        if create_result["result"]:
            ret["result"] = True
            ret["comment"] = create_result["comment"]
            ret["changes"] = create_result["changes"]
            log.info(f"Created user {user_dn}")
            return ret
        else:
            ret["result"] = False
            ret["comment"] = (
                f"Failed to create user {user_dn}: {create_result['comment']}"
            )
            return ret
    else:
        # Call update_user (no password update, as per previous instructions)
        update_result = __salt__["ldap_utils.update_user"](
            spec_name,
            user_dn,
            uid,
            cn,
            sn,
            description,
            uid_number=None,
            gid_number=None,
            home_directory=None,
            login_shell=None,
        )
        if update_result["result"]:
            ret["result"] = True
            ret["comment"] = update_result["comment"]
            ret["changes"] = update_result["changes"]
            log.info(f"Updated user {user_dn}")
            return ret
        else:
            ret["result"] = False
            ret["comment"] = (
                f"Failed to update user {user_dn}: {update_result['comment']}"
            )
            return ret


def group_present(name, spec_name, base_dn, cn, description=None, members=None):
    """
    Ensure that a single group exists in the LDAP directory, creating or updating as needed.

    Args:
        name (str): The name of the state (used for identification in Salt).
        spec_name (str): The name of the connection specification to use.
        base_dn (str): The base distinguished name under which the group will be created/updated (e.g., 'ou=groups,dc=rsc,dc=gacyberrange,dc=org').
        cn (str): The common name (CN) of the group.
        description (str, optional): The description to set for the group.
        members (list, optional): List of member DNs to set for the group.

    Returns:
        dict: A dictionary containing the state result.
    """
    ret = {"name": name, "result": True, "changes": {}, "comment": ""}

    # Check if ldap_utils module is available
    if "ldap_utils.get_connect_spec" not in __salt__:
        ret["result"] = False
        ret["comment"] = (
            "ldap_utils module not found. Please ensure the module is synced to the minion with 'saltutil.sync_modules'."
        )
        return ret

    # Check if ldap_utils module is available
    if "ldap_utils.get_connect_spec" not in __salt__:
        ret["result"] = False
        ret["comment"] = (
            "ldap_utils module not found. Please ensure the module is synced to the minion."
        )
        return ret

    # Check if connection spec exists
    conn_result = __salt__["ldap_utils.get_connect_spec"](spec_name)
    if not conn_result["success"]:
        ret["result"] = False
        ret["comment"] = (
            f"Connection spec '{spec_name}' not found: {conn_result['error']}"
        )
        return ret

    # Construct group DN, e.g., 'cn=cn,base_dn'
    group_dn = f"cn={cn},{base_dn}"

    # Prepare attributes for existence check (mirroring fixed attributes in create_group/update_group)
    attributes = {"objectClass": ["groupOfNames"], "cn": cn}
    if description:
        attributes["description"] = description
    if members:
        attributes["member"] = members  # groupOfNames uses full member DNs
    else:
        # groupOfNames requires at least one member; create_group/update_group
        # default to the group's own DN when none is provided.
        attributes["member"] = [group_dn]

    # Check if group exists and attributes match
    if "ldap_utils.dn_exists" not in __salt__:
        ret["result"] = False
        ret["comment"] = (
            "ldap_utils.dn_exists function not found. Please ensure the module is synced to the minion."
        )
        return ret
    check_result = __salt__["ldap_utils.dn_exists"](spec_name, group_dn, attributes)
    if not check_result["result"]:
        if "No such object" in check_result["comment"]:
            exists = False
            attributes_match = False
        else:
            ret["result"] = False
            ret["comment"] = (
                f"Error checking group {group_dn}: {check_result['comment']}"
            )
            return ret
    else:
        exists = check_result.get("exists", False)
        attributes_match = check_result.get("attributes_match", False)

    # If exists and matches, we're done
    if exists and attributes_match:
        ret["comment"] = (
            f"Group {group_dn} already exists with matching attributes and members."
        )
        return ret

    # Create or update based on existence
    if not exists:
        # Call create_group
        if "ldap_utils.create_group" not in __salt__:
            ret["result"] = False
            ret["comment"] = (
                "ldap_utils.create_group function not found. Please ensure the module is synced to the minion."
            )
            return ret
        create_result = __salt__["ldap_utils.create_group"](
            spec_name, group_dn, cn, description, members, gid_number=None
        )
        if create_result["result"]:
            ret["result"] = True
            ret["comment"] = create_result["comment"]
            ret["changes"] = create_result["changes"]
            log.info(f"Created group {group_dn}")
            return ret
        else:
            ret["result"] = False
            ret["comment"] = (
                f"Failed to create group {group_dn}: {create_result['comment']}"
            )
            return ret
    else:
        # Call update_group
        if "ldap_utils.update_group" not in __salt__:
            ret["result"] = False
            ret["comment"] = (
                "ldap_utils.update_group function not found. Please ensure the module is synced to the minion."
            )
            return ret
        # Call update_group
        update_result = __salt__["ldap_utils.update_group"](
            spec_name, group_dn, cn, description, members, gid_number=None
        )
        if update_result["result"]:
            ret["result"] = True
            ret["comment"] = update_result["comment"]
            ret["changes"] = update_result["changes"]
            log.info(f"Updated group {group_dn}")
            return ret
        else:
            ret["result"] = False
            ret["comment"] = (
                f"Failed1 to update group {group_dn}: {update_result['comment']}"
            )
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
