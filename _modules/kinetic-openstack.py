# -*- coding: utf-8 -*-
"""
OpenStack Module for Kinetic - Keystone Focus
============================================

This module provides functions to interact with OpenStack Keystone services
for managing projects, roles, and LDAP group associations.
"""

import json
import logging
import os

from salt.exceptions import CommandExecutionError

__virtualname__ = "kinetic-openstack"

log = logging.getLogger(__name__)

try:
    from openstack import connection, exceptions

    HAS_OPENSTACK = True
except ImportError:
    HAS_OPENSTACK = False


def __virtual__():
    try:
        import openstack

        return __virtualname__
    except ImportError:
        return (False, "openstack module not installed.")


def _get_connection(cloud=None):
    """
    Create an OpenStack connection using a cloud configuration name from os-cloud-config.
    Returns None if no cloud name is provided.

    Args:
        cloud (str): Name of the cloud configuration from clouds.yaml.
                     This corresponds to os-cloud-config settings typically found in ~/.config/openstack/clouds.yaml.
                     If not provided, the function will return None.

    Returns:
        Connection object to OpenStack or None if no cloud name is provided
    """
    if cloud is None:
        log.warning(
            "No cloud configuration name provided for os-cloud-config. Connection attempt aborted."
        )
        return None

    # Use cloud configuration from clouds.yaml (os-cloud-config)
    try:
        conn = connection.from_config(cloud=cloud)
        return conn
    except exceptions.SDKException as e:
        raise CommandExecutionError(
            f"Failed to connect to OpenStack with cloud config {cloud} from os-cloud-config: {str(e)}. "
            f"Ensure the cloud name is defined in ~/.config/openstack/clouds.yaml or set OS_CLIENT_CONFIG_FILE."
        )


def get_projects(cloud=None):
    """
    List all projects in OpenStack

    Args:
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        list: List of project details or empty list if no cloud configuration is provided

    CLI Example:

    .. code-block:: bash

        salt '*' openstack.get_projects
    """
    conn = _get_connection(cloud)
    if conn is None:
        return []
    try:
        projects = [
            {"id": project.id, "name": project.name}
            for project in conn.identity.projects()
        ]
        return projects
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to list projects: {str(e)}")
    finally:
        conn.close()


def get_roles(cloud=None):
    """
    List all roles in OpenStack

    Args:
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        list: List of role details or empty list if no cloud configuration is provided

    CLI Example:

    .. code-block:: bash

        salt '*' openstack.get_roles
    """
    conn = _get_connection(cloud)
    if conn is None:
        return []
    try:
        roles = [{"id": role.id, "name": role.name} for role in conn.identity.roles()]
        return roles
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to list roles: {str(e)}")
    finally:
        conn.close()


def get_groups(cloud=None):
    """
    List all groups in OpenStack

    Args:
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        list: List of group details or empty list if no cloud configuration is provided

    CLI Example:

    .. code-block:: bash

        salt '*' openstack.get_groups
    """
    conn = _get_connection(cloud)
    if conn is None:
        return []
    try:
        groups = [
            {"id": group.id, "name": group.name} for group in conn.identity.groups()
        ]
        return groups
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to list groups: {str(e)}")
    finally:
        conn.close()


def create_project(name, description=None, domain_id="default", cloud=None):
    """
    Create a new project in OpenStack

    Args:
        name (str): Name of the project
        description (str): Description of the project (optional)
        domain_id (str): Domain ID for the project (default is 'default')
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict: Information about the created project or None if no cloud configuration is provided

    CLI Example:

    .. code-block:: bash

        salt '*' openstack.create_project myproject "My Project Description"
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        project = conn.identity.create_project(
            name=name, description=description, domain_id=domain_id, is_enabled=True
        )
        return {
            "id": project.id,
            "name": project.name,
            "description": project.description,
            "domain_id": project.domain_id,
        }
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to create project: {str(e)}")
    finally:
        conn.close()


def update_project(name_or_id, cloud=None, **updates):
    """
    Update attributes of an existing project in OpenStack

    Args:
        name_or_id (str): Name or ID of the project to update
        cloud (str): Optional name of the cloud configuration from clouds.yaml
        **updates: Dictionary of attributes to update (e.g., description, is_enabled)

    Returns:
        dict: Updated project information, or None if no cloud configuration is provided

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic-openstack.update_project myproject description="Updated description" is_enabled=True
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        project = conn.identity.find_project(name_or_id)
        if not project:
            raise CommandExecutionError(f"Project {name_or_id} not found")

        updated_project = conn.identity.update_project(project, **updates)
        return {
            "id": updated_project.id,
            "name": updated_project.name,
            "description": updated_project.description,
            "domain_id": updated_project.domain_id,
            "is_enabled": updated_project.is_enabled,
        }
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to update project: {str(e)}")
    finally:
        conn.close()


def delete_project(name_or_id, cloud=None):
    """
    Delete a project in OpenStack

    Args:
        name_or_id (str): Name or ID of the project to delete
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        bool: True if deletion was successful, False if no cloud configuration is provided

    CLI Example:

    .. code-block:: bash

        salt '*' openstack.delete_project myproject
    """
    conn = _get_connection(cloud)
    if conn is None:
        return False
    try:
        project = conn.identity.find_project(name_or_id)
        if not project:
            raise CommandExecutionError(f"Project {name_or_id} not found")

        conn.identity.delete_project(project)
        return True
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to delete project: {str(e)}")
    finally:
        conn.close()


def assign_role_to_group(
    role_name_or_id,
    group_name_or_id,
    project_name_or_id=None,
    domain_name_or_id=None,
    cloud=None,
):
    """
    Assign a role to a group, optionally scoped to a project or domain

    Args:
        role_name_or_id (str): Name or ID of the role
        group_name_or_id (str): Name or ID of the group
        project_name_or_id (str): Name or ID of the project (optional)
        domain_name_or_id (str): Name or ID of the domain (optional)
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        bool: True if assignment was successful, False if no cloud configuration is provided

    CLI Example:

    .. code-block:: bash

        salt '*' openstack.assign_role_to_group member mygroup myproject
    """
    conn = _get_connection(cloud)
    if conn is None:
        return False
    try:
        role = conn.identity.find_role(role_name_or_id)
        if not role:
            raise CommandExecutionError(f"Role {role_name_or_id} not found")

        group = conn.identity.find_group(group_name_or_id)
        if not group:
            raise CommandExecutionError(f"Group {group_name_or_id} not found")

        if project_name_or_id:
            project = conn.identity.find_project(project_name_or_id)
            if not project:
                raise CommandExecutionError(f"Project {project_name_or_id} not found")
            conn.identity.grant_role(role.id, group=group.id, project=project.id)
        elif domain_name_or_id:
            domain = conn.identity.find_domain(domain_name_or_id)
            if not domain:
                raise CommandExecutionError(f"Domain {domain_name_or_id} not found")
            conn.identity.grant_role(role.id, group=group.id, domain=domain.id)
        else:
            raise CommandExecutionError(
                "Either project or domain must be specified for role assignment"
            )

        return True
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to assign role: {str(e)}")
    finally:
        conn.close()


def revoke_role_from_group(
    role_name_or_id,
    group_name_or_id,
    project_name_or_id=None,
    domain_name_or_id=None,
    cloud=None,
):
    """
    Revoke a role from a group, scoped to a project or domain

    Args:
        role_name_or_id (str): Name or ID of the role
        group_name_or_id (str): Name or ID of the group
        project_name_or_id (str): Name or ID of the project (optional)
        domain_name_or_id (str): Name or ID of the domain (optional)
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        bool: True if revocation was successful, False if no cloud configuration is provided

    CLI Example:

    .. code-block:: bash

        salt '*' openstack.revoke_role_from_group member mygroup myproject
    """
    conn = _get_connection(cloud)
    if conn is None:
        return False
    try:
        role = conn.identity.find_role(role_name_or_id)
        if not role:
            raise CommandExecutionError(f"Role {role_name_or_id} not found")

        group = conn.identity.find_group(group_name_or_id)
        if not group:
            raise CommandExecutionError(f"Group {group_name_or_id} not found")

        if project_name_or_id:
            project = conn.identity.find_project(project_name_or_id)
            if not project:
                raise CommandExecutionError(f"Project {project_name_or_id} not found")
            conn.identity.revoke_role(role.id, group=group.id, project=project.id)
        elif domain_name_or_id:
            domain = conn.identity.find_domain(domain_name_or_id)
            if not domain:
                raise CommandExecutionError(f"Domain {domain_name_or_id} not found")
            conn.identity.revoke_role(role.id, group=group.id, domain=domain.id)
        else:
            raise CommandExecutionError(
                "Either project or domain must be specified for role revocation"
            )

        return True
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to revoke role: {str(e)}")
    finally:
        conn.close()
