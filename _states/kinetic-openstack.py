# -*- coding: utf-8 -*-
"""
OpenStack Keystone State Module
==============================
This state module provides functionalities to manage OpenStack Keystone resources.
It interfaces with the OpenStack module to perform operations such as creating,
updating, and deleting projects, roles, and associating them with LDAP groups
within an OpenStack cloud environment.

Dependencies:
    This module requires the OpenStack SDK for Python to interact with OpenStack services.
    To install the necessary dependencies, use the following command:
        pip install openstacksdk
    Ensure that the SDK is installed on the system where this Salt module is executed.
    Additionally, OpenStack authentication credentials must be set either via environment
    variables (OS_AUTH_URL, OS_USERNAME, OS_PASSWORD, etc.) or passed as arguments.

Usage:@
    This state can be used to ensure the desired state of OpenStack Keystone resources.
    It supports management of projects, roles, and group-role assignments.

Example:
    ensure_openstack_project:
      openstack.project_present:
        - name: my-project
        - description: "A test project"
        - enabled: True

    ensure_role_assignment:
      openstack.role_assignment_present:
        - role_name: member
        - project_name: my-project
        - group_name: ldap-group1
"""

import logging

from openstack import connection, exceptions

log = logging.getLogger(__name__)

__virtualname__ = "kinetic_openstack"


def __virtual__():
    """
    Only load if the openstack module is available in __salt__
    """
    if "kinetic_openstack.get_projects" in __salt__:
        return __virtualname__
    return False


def project_present(name, description=None, enabled=True, **kwargs):
    """
    Ensure that an OpenStack project is present.

    Args:
        name (str): Name of the project.
        description (str, optional): Description of the project.
        enabled (bool, optional): Whether the project is enabled. Defaults to True.
        **kwargs: Additional arguments to pass to the OpenStack API.

    Returns:
        dict: A dictionary with the result of the operation.
    """
    ret = {"name": name, "result": True, "changes": {}, "comment": ""}

    # Check if project already exists
    cloud_name = kwargs.get("cloud")
    if cloud_name is None:
        return {
            "name": name,
            "result": False,
            "changes": {},
            "comment": "No cloud configuration name provided. Specify 'cloud' in state, set 'openstack:cloud_name' in pillar, or set OS_CLOUD environment variable.",
        }
    project = __salt__["kinetic_openstack.get_projects"](cloud=cloud_name)
    project = next((p for p in project if p["name"] == name), None)
    if project:
        ret["comment"] = f"Project {name} already exists."
        # Check if description or enabled status needs update

        updates = {}
        if description is not None and project.get("description") != description:
            updates["description"] = description
        if project.get("is_enabled") != enabled:
            updates["is_enabled"] = enabled

        if updates:
            # Check if updates are actually different from current project state
            actual_changes = {}
            for key, value in updates.items():
                current_value = project.get(key)
                if current_value != value:
                    actual_changes[key] = value

            if not actual_changes:
                ret["comment"] = f"Project {name} already has the desired attributes."
                return ret

            if __opts__["test"]:
                ret["result"] = None
                ret["comment"] = (
                    f"Project {name} would be updated with {actual_changes}."
                )
                return ret
            try:
                result = __salt__["kinetic_openstack.update_project"](
                    name, cloud=cloud_name, **updates
                )
                if result:
                    # Verify if changes were actually applied by checking result
                    applied_changes = {}
                    for key, value in actual_changes.items():
                        if result.get(key) == value:
                            applied_changes[key] = value
                    if applied_changes:
                        ret["changes"] = {"updated": applied_changes}
                        ret["comment"] = (
                            f"Project {name} updated successfully with {applied_changes}."
                        )
                    else:
                        ret["comment"] = (
                            f"Project {name} update attempted, but no changes were applied."
                        )
                else:
                    ret["result"] = False
                    ret["comment"] = f"Failed to update project {name}."
            except Exception as e:
                ret["result"] = False
                ret["comment"] = f"Error updating project {name}: {str(e)}"
        return ret

    # If project does not exist, create it
    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = f"Project {name} would be created."
        return ret

    try:
        # Ensure cloud is not duplicated from kwargs
        filtered_kwargs = {k: v for k, v in kwargs.items() if k != "cloud"}
        result = __salt__["kinetic_openstack.create_project"](
            name=name,
            description=description,
            cloud=cloud_name,
            **filtered_kwargs,
        )
        if result:
            ret["changes"] = {"created": name}
            ret["comment"] = f"Project {name} created successfully."
        else:
            ret["result"] = False
            ret["comment"] = f"Failed to create project {name}."
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Error creating project {name}: {str(e)}"

    return ret


def project_absent(name, **kwargs):
    """
    Ensure that an OpenStack project is absent.

    Args:
        name (str): Name of the project to delete.

    Returns:
        dict: A dictionary with the result of the operation.
    """
    ret = {"name": name, "result": True, "changes": {}, "comment": ""}

    # Check if project exists
    # Check if project already exists
    cloud_name = kwargs.get("cloud")
    if cloud_name is None:
        return {
            "name": name,
            "result": False,
            "changes": {},
            "comment": "No cloud configuration name provided. Specify 'cloud' in state.",
        }
    project = __salt__["kinetic_openstack.get_projects"](cloud=cloud_name)
    project = next((p for p in project if p["name"] == name), None)
    if not project:
        ret["comment"] = f"Project {name} does not exist."
        return ret

    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = f"Project {name} would be deleted."
        return ret

    try:
        # Ensure cloud is not duplicated from kwargs
        filtered_kwargs = {k: v for k, v in kwargs.items() if k != "cloud"}
        result = __salt__["kinetic_openstack.delete_project"](
            name, cloud=cloud_name, **filtered_kwargs
        )
        if result:
            ret["changes"] = {"deleted": name}
            ret["comment"] = f"Project {name} deleted successfully."
        else:
            ret["result"] = False
            ret["comment"] = f"Failed to delete project {name}."
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Error deleting project {name}: {str(e)}"

    return ret


def role_assignment_present(
    name,
    role_name,
    project_name,
    group_name=None,
    user_name=None,
    group_domain=None,
    project_domain=None,
    **kwargs,
):
    """
    Ensure that a role is assigned to a group or user in a specific project.

    Args:
        role_name (str): Name of the role to assign.
        project_name (str): Name of the project to assign the role in.
        group_name (str, optional): Name of the group to assign the role to.
        user_name (str, optional): Name of the user to assign the role to.
        group_domain (str, optional): Domain of the group.
        project_domain (str, optional): Domain of the project.
        Note: Either group_name or user_name must be provided, but not both.

    Returns:
        dict: A dictionary with the result of the operation.
    """
    if (group_name and user_name) or (not group_name and not user_name):
        return {
            "name": role_name,
            "result": False,
            "changes": {},
            "comment": "Either group_name or user_name must be provided, but not both.",
        }

    ret = {"name": role_name, "result": True, "changes": {}, "comment": ""}
    entity_type = "group" if group_name else "user"
    entity_name = group_name or user_name

    # Check if role assignment exists
    cloud_name = kwargs.get("cloud")
    if cloud_name is None:
        cloud_name = pillar.get("openstack", {}).get("cloud_name", None)
    if cloud_name is None:
        return {
            "name": role_name,
            "result": False,
            "changes": {},
            "comment": "No cloud configuration name provided. Specify 'cloud' in state or set 'openstack:cloud_name' in pillar.",
        }
    assignment_exists = __salt__["kinetic_openstack.check_role_assignment"](
        role_name=role_name,
        project_name_or_id=project_name,
        group_name=group_name,
        user_name=user_name,
        cloud=cloud_name,
    )
    if assignment_exists:
        ret["comment"] = (
            f"Role {role_name} is already assigned to {entity_type} {entity_name} in project {project_name}."
        )
        return ret

    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = (
            f"Role {role_name} would be assigned to {entity_type} {entity_name} in project {project_name}."
        )
        return ret

    try:
        # Ensure cloud and name are not duplicated from kwargs
        filtered_kwargs = {
            k: v for k, v in kwargs.items() if k not in ["cloud", "name"]
        }
        result = __salt__["kinetic_openstack.assign_role_to_group"](
            role_name_or_id=role_name,
            group_name_or_id=group_name if group_name else user_name,
            project_name_or_id=project_name,
            group_domain=group_domain,
            project_domain=project_domain,
            cloud=cloud_name,
            **filtered_kwargs,
        )
        if result:
            ret["changes"] = {
                "assigned": f"{role_name} to {entity_type} {entity_name} in {project_name}"
            }
            ret["comment"] = (
                f"Role {role_name} assigned successfully to {entity_type} {entity_name}."
            )
        else:
            ret["result"] = False
            ret["comment"] = (
                f"Failed to assign role {role_name} to {entity_type} {entity_name}."
            )
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Error assigning role {role_name}: {str(e)}"

    return ret


def role_assignment_absent(
    name,
    role_name,
    project_name,
    group_name=None,
    user_name=None,
    group_domain=None,
    project_domain=None,
    **kwargs,
):
    """
    Ensure that a role assignment is absent for a group or user in a specific project.

    Args:
        role_name (str): Name of the role to unassign.
        project_name (str): Name of the project to unassign the role from.
        group_name (str, optional): Name of the group to unassign the role from.
        user_name (str, optional): Name of the user to unassign the role from.
        group_domain (str, optional): Domain of the group.
        project_domain (str, optional): Domain of the project.
        Note: Either group_name or user_name must be provided, but not both.

    Returns:
        dict: A dictionary with the result of the operation.
    """
    if (group_name and user_name) or (not group_name and not user_name):
        return {
            "name": role_name,
            "result": False,
            "changes": {},
            "comment": "Either group_name or user_name must be provided, but not both.",
        }

    ret = {"name": role_name, "result": True, "changes": {}, "comment": ""}
    entity_type = "group" if group_name else "user"
    entity_name = group_name or user_name

    # Check if role assignment exists
    cloud_name = kwargs.get("cloud")
    if cloud_name is None:
        return {
            "name": role_name,
            "result": False,
            "changes": {},
            "comment": "No cloud configuration name provided. Specify 'cloud' in state.",
        }
    assignment_exists = __salt__["kinetic_openstack.check_role_assignment"](
        role_name=role_name,
        project_name_or_id=project_name,
        group_name=group_name,
        user_name=user_name,
        cloud=cloud_name,
    )
    if not assignment_exists:
        ret["comment"] = (
            f"Role {role_name} is not assigned to {entity_type} {entity_name} in project {project_name}."
        )
        return ret

    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = (
            f"Role {role_name} would be unassigned from {entity_type} {entity_name} in project {project_name}."
        )
        return ret

    try:
        # Ensure cloud and name are not duplicated from kwargs
        filtered_kwargs = {
            k: v for k, v in kwargs.items() if k not in ["cloud", "name"]
        }
        result = __salt__["kinetic_openstack.revoke_role_from_group"](
            role_name_or_id=role_name,
            group_name_or_id=group_name if group_name else user_name,
            project_name_or_id=project_name,
            group_domain=group_domain,
            project_domain=project_domain,
            cloud=cloud_name,
            **filtered_kwargs,
        )
        if result:
            ret["changes"] = {
                "unassigned": f"{role_name} from {entity_type} {entity_name} in {project_name}"
            }
            ret["comment"] = (
                f"Role {role_name} unassigned successfully from {entity_type} {entity_name}."
            )
        else:
            ret["result"] = False
            ret["comment"] = (
                f"Failed to unassign role {role_name} from {entity_type} {entity_name}."
            )
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Error unassigning role {role_name}: {str(e)}"

    return ret


def health_check(name, timeout=180, interval=5, **kwargs):
    """
    Ensure the OpenStack Keystone API is reachable and issuing tokens.

    Acts as a polling gate for dependent federation states - a Helm release
    reporting "deployed" does not guarantee the external Ingress/HTTPRoute/DNS
    path to Keystone is actually ready yet. Other states should `require`
    this one rather than just requiring the Helm release.

    Args:
        name (str): Arbitrary state ID.
        timeout (int): Maximum seconds to wait for Keystone to become reachable. Defaults to 180.
        interval (int): Seconds between retries. Defaults to 5.

    Example:

    .. code-block:: yaml

        keystone_available:
          kinetic_openstack.health_check:
            - cloud: rsc
            - timeout: 180
            - interval: 5
    """
    ret = {"name": name, "result": True, "changes": {}, "comment": ""}

    cloud_name = kwargs.get("cloud")
    if cloud_name is None:
        return {
            "name": name,
            "result": False,
            "changes": {},
            "comment": "No cloud configuration name provided. Specify 'cloud' in state.",
        }

    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = f"Would check that Keystone ({cloud_name}) is reachable."
        return ret

    try:
        result = __salt__["kinetic_openstack.check_health"](
            cloud=cloud_name, timeout=timeout, interval=interval
        )
        ret["result"] = bool(result.get("healthy"))
        ret["comment"] = result.get("message", "")
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Error checking Keystone health: {str(e)}"

    return ret


def identity_provider_present(
    name,
    domain_name=None,
    description=None,
    enabled=True,
    remote_ids=None,
    **kwargs,
):
    """
    Ensure an OS-FEDERATION identity provider exists, scoped to an existing
    Keystone domain.

    This never creates the domain - it must already exist (e.g. a domain
    owned by an LDAP backend). If the identity provider already exists but
    is bound to a *different* domain than requested, this state refuses to
    change it automatically, since remapping an IdP's domain would break
    every mapping/assignment built against the current domain.

    Args:
        name (str): The identity provider ID (e.g. "keycloak").
        domain_name (str): Name of the existing Keystone domain to scope the
            IdP to (e.g. "rsc"). Required.
        description (str, optional): Description of the identity provider.
        enabled (bool, optional): Whether the identity provider is enabled. Defaults to True.
        remote_ids (list, optional): List of remote IdP issuer URLs.

    Example:

    .. code-block:: yaml

        keystone_keycloak_idp:
          kinetic_openstack.identity_provider_present:
            - name: keycloak
            - domain_name: rsc
            - remote_ids:
              - https://keycloak.rsc.gacyberrange.org/realms/rsc
            - cloud: rsc
    """
    ret = {"name": name, "result": True, "changes": {}, "comment": ""}

    cloud_name = kwargs.get("cloud")
    if cloud_name is None:
        return {
            "name": name,
            "result": False,
            "changes": {},
            "comment": "No cloud configuration name provided. Specify 'cloud' in state.",
        }

    if not domain_name:
        return {
            "name": name,
            "result": False,
            "changes": {},
            "comment": "domain_name is required (the existing domain to scope this identity provider to).",
        }

    remote_ids = remote_ids or []

    domain = __salt__["kinetic_openstack.get_domain"](domain_name, cloud=cloud_name)
    if not domain:
        return {
            "name": name,
            "result": False,
            "changes": {},
            "comment": f"Domain '{domain_name}' does not exist. This state does not create domains.",
        }

    existing = __salt__["kinetic_openstack.get_identity_provider"](
        name, cloud=cloud_name
    )

    if existing:
        if existing.get("domain_id") != domain["id"]:
            return {
                "name": name,
                "result": False,
                "changes": {},
                "comment": (
                    f"Identity provider '{name}' already exists but is bound to domain_id "
                    f"'{existing.get('domain_id')}', not domain '{domain_name}' ({domain['id']}). "
                    "Refusing to change an existing identity provider's domain automatically - "
                    "this would break every mapping/assignment built against the current domain. "
                    "Resolve manually if a domain change is intended."
                ),
            }

        updates = {}
        if existing.get("enabled") != enabled:
            updates["enabled"] = enabled
        if description is not None and existing.get("description") != description:
            updates["description"] = description
        if sorted(existing.get("remote_ids") or []) != sorted(remote_ids):
            updates["remote_ids"] = remote_ids

        if not updates:
            ret["comment"] = (
                f"Identity provider '{name}' already exists and matches the desired state."
            )
            return ret

        if __opts__["test"]:
            ret["result"] = None
            ret["comment"] = f"Identity provider '{name}' would be updated with {updates}."
            return ret

        try:
            __salt__["kinetic_openstack.update_identity_provider"](
                name, cloud=cloud_name, **updates
            )
            ret["changes"] = {"updated": updates}
            ret["comment"] = f"Identity provider '{name}' updated successfully."
        except Exception as e:
            ret["result"] = False
            ret["comment"] = f"Error updating identity provider '{name}': {str(e)}"
        return ret

    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = f"Identity provider '{name}' would be created in domain '{domain_name}'."
        return ret

    try:
        __salt__["kinetic_openstack.create_identity_provider"](
            name,
            domain_id=domain["id"],
            description=description,
            enabled=enabled,
            remote_ids=remote_ids,
            cloud=cloud_name,
        )
        ret["changes"] = {"created": name}
        ret["comment"] = f"Identity provider '{name}' created in domain '{domain_name}'."
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Error creating identity provider '{name}': {str(e)}"

    return ret


def mapping_present(name, rules, **kwargs):
    """
    Ensure an OS-FEDERATION mapping exists with the given rules.

    Args:
        name (str): The mapping ID (e.g. "keycloak_openid").
        rules (list): List of mapping rule dicts (local/remote), per the
            Keystone federation mapping schema.

    Example:

    .. code-block:: yaml

        keystone_keycloak_mapping:
          kinetic_openstack.mapping_present:
            - name: keycloak_openid
            - rules:
              - local:
                  - user:
                      name: "{0}"
                      domain:
                        name: rsc
                  - group:
                      name: "{1}"
                      domain:
                        name: rsc
                remote:
                  - type: OIDC-preferred_username
                  - type: HTTP_OIDC_GROUPS
            - cloud: rsc
    """
    ret = {"name": name, "result": True, "changes": {}, "comment": ""}

    cloud_name = kwargs.get("cloud")
    if cloud_name is None:
        return {
            "name": name,
            "result": False,
            "changes": {},
            "comment": "No cloud configuration name provided. Specify 'cloud' in state.",
        }

    if not rules:
        return {
            "name": name,
            "result": False,
            "changes": {},
            "comment": "rules is required and must not be empty.",
        }

    existing = __salt__["kinetic_openstack.get_mapping"](name, cloud=cloud_name)

    if existing:
        if existing.get("rules") == rules:
            ret["comment"] = f"Mapping '{name}' already matches the desired rules."
            return ret

        if __opts__["test"]:
            ret["result"] = None
            ret["comment"] = f"Mapping '{name}' rules would be updated."
            return ret

        try:
            __salt__["kinetic_openstack.update_mapping"](name, rules, cloud=cloud_name)
            ret["changes"] = {"updated": "rules"}
            ret["comment"] = f"Mapping '{name}' rules updated successfully."
        except Exception as e:
            ret["result"] = False
            ret["comment"] = f"Error updating mapping '{name}': {str(e)}"
        return ret

    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = f"Mapping '{name}' would be created."
        return ret

    try:
        __salt__["kinetic_openstack.create_mapping"](name, rules, cloud=cloud_name)
        ret["changes"] = {"created": name}
        ret["comment"] = f"Mapping '{name}' created successfully."
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Error creating mapping '{name}': {str(e)}"

    return ret


def federation_protocol_present(name, idp_name, mapping_id, **kwargs):
    """
    Ensure a federation protocol is registered for an identity provider,
    pointing at the given mapping.

    Args:
        name (str): The protocol ID (e.g. "openid").
        idp_name (str): The identity provider ID this protocol belongs to.
        mapping_id (str): The mapping ID to associate with this protocol.

    Example:

    .. code-block:: yaml

        keystone_keycloak_protocol:
          kinetic_openstack.federation_protocol_present:
            - name: openid
            - idp_name: keycloak
            - mapping_id: keycloak_openid
            - cloud: rsc
    """
    ret = {"name": name, "result": True, "changes": {}, "comment": ""}

    cloud_name = kwargs.get("cloud")
    if cloud_name is None:
        return {
            "name": name,
            "result": False,
            "changes": {},
            "comment": "No cloud configuration name provided. Specify 'cloud' in state.",
        }

    existing = __salt__["kinetic_openstack.get_federation_protocol"](
        idp_name, name, cloud=cloud_name
    )

    if existing:
        if existing.get("mapping_id") == mapping_id:
            ret["comment"] = (
                f"Federation protocol '{name}' on identity provider '{idp_name}' "
                f"already uses mapping '{mapping_id}'."
            )
            return ret

        if __opts__["test"]:
            ret["result"] = None
            ret["comment"] = (
                f"Federation protocol '{name}' on '{idp_name}' would be updated "
                f"to use mapping '{mapping_id}'."
            )
            return ret

        try:
            __salt__["kinetic_openstack.update_federation_protocol"](
                idp_name, name, mapping_id, cloud=cloud_name
            )
            ret["changes"] = {"updated": {"mapping_id": mapping_id}}
            ret["comment"] = (
                f"Federation protocol '{name}' on '{idp_name}' updated to use "
                f"mapping '{mapping_id}'."
            )
        except Exception as e:
            ret["result"] = False
            ret["comment"] = f"Error updating federation protocol '{name}': {str(e)}"
        return ret

    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = (
            f"Federation protocol '{name}' would be created on identity provider "
            f"'{idp_name}' using mapping '{mapping_id}'."
        )
        return ret

    try:
        __salt__["kinetic_openstack.create_federation_protocol"](
            idp_name, name, mapping_id, cloud=cloud_name
        )
        ret["changes"] = {"created": name}
        ret["comment"] = (
            f"Federation protocol '{name}' created on identity provider "
            f"'{idp_name}' using mapping '{mapping_id}'."
        )
    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Error creating federation protocol '{name}': {str(e)}"

    return ret
