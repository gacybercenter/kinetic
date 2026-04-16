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

Usage:
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

log = logging.getLogger(__name__)

__virtualname__ = "kinetic-openstack"


def __virtual__():
    """
    Only load if the openstack module is available in __salt__
    """
    if "kinetic-openstack.get_projects" in __salt__:
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
    cloud_name = kwargs.get("auth_args", os.environ.get("OS_CLOUD", "openstack"))
    project = __salt__["kinetic-openstack.get_projects"](auth_args=cloud_name)
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
            if __opts__["test"]:
                ret["result"] = None
                ret["comment"] = f"Project {name} would be updated with {updates}."
                return ret
            try:
                result = __salt__["kinetic-openstack.update_project"](
                    name, auth_args=cloud_name, **updates
                )
                if result:
                    ret["changes"] = {"updated": updates}
                    ret["comment"] = f"Project {name} updated successfully."
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
        result = __salt__["kinetic-openstack.create_project"](
            name=name,
            description=description,
            enabled=enabled,
            auth_args=cloud_name,
            **kwargs,
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


def project_absent(name):
    """
    Ensure that an OpenStack project is absent.

    Args:
        name (str): Name of the project to delete.

    Returns:
        dict: A dictionary with the result of the operation.
    """
    ret = {"name": name, "result": True, "changes": {}, "comment": ""}

    # Check if project exists
    cloud_name = kwargs.get("auth_args", os.environ.get("OS_CLOUD", "openstack"))
    project = __salt__["kinetic-openstack.get_projects"](auth_args=cloud_name)
    project = next((p for p in project if p["name"] == name), None)
    if not project:
        ret["comment"] = f"Project {name} does not exist."
        return ret

    if __opts__["test"]:
        ret["result"] = None
        ret["comment"] = f"Project {name} would be deleted."
        return ret

    try:
        result = __salt__["kinetic-openstack.delete_project"](
            name, auth_args=cloud_name
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


def role_assignment_present(role_name, project_name, group_name=None, user_name=None):
    """
    Ensure that a role is assigned to a group or user in a specific project.

    Args:
        role_name (str): Name of the role to assign.
        project_name (str): Name of the project to assign the role in.
        group_name (str, optional): Name of the group to assign the role to.
        user_name (str, optional): Name of the user to assign the role to.
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

    # Check if role assignment already exists
    cloud_name = kwargs.get("auth_args", os.environ.get("OS_CLOUD", "openstack"))
    assignment_exists = __salt__["kinetic-openstack.check_role_assignment"](
        role_name=role_name,
        project_name=project_name,
        group_name=group_name,
        user_name=user_name,
        auth_args=cloud_name,
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
        result = __salt__["kinetic-openstack.assign_role_to_group"](
            role_name_or_id=role_name,
            group_name_or_id=group_name if group_name else user_name,
            project_name_or_id=project_name,
            auth_args=cloud_name,
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


def role_assignment_absent(role_name, project_name, group_name=None, user_name=None):
    """
    Ensure that a role assignment is absent for a group or user in a specific project.

    Args:
        role_name (str): Name of the role to unassign.
        project_name (str): Name of the project to unassign the role from.
        group_name (str, optional): Name of the group to unassign the role from.
        user_name (str, optional): Name of the user to unassign the role from.
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
    cloud_name = kwargs.get("auth_args", os.environ.get("OS_CLOUD", "openstack"))
    assignment_exists = __salt__["kinetic-openstack.check_role_assignment"](
        role_name=role_name,
        project_name=project_name,
        group_name=group_name,
        user_name=user_name,
        auth_args=cloud_name,
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
        result = __salt__["kinetic-openstack.revoke_role_from_group"](
            role_name_or_id=role_name,
            group_name_or_id=group_name if group_name else user_name,
            project_name_or_id=project_name,
            auth_args=cloud_name,
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
