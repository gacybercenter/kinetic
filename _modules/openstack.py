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

__virtualname__ = "openstack"

log = logging.getLogger(__name__)

try:
    from openstack import connection, exceptions

    HAS_OPENSTACK = True
except ImportError:
    pass


@decorators.memoize
def __virtual__():
    if HAS_OPENSTACK:
        return __virtualname__
    return (
        False,
        "The openstack module could not be loaded: OpenStack SDK is not installed. Install with 'pip install openstacksdk'.",
    )


def _get_connection(auth_args=None):
    """
    Create an OpenStack connection using provided cloud name or environment variables.

    Args:
        auth_args (str): Name of the cloud configuration from clouds.yaml

    Returns:
        Connection object to OpenStack
    """
    if auth_args is None:
        auth_args = {
            "auth_url": os.environ.get("OS_AUTH_URL"),
            "project_name": os.environ.get("OS_PROJECT_NAME"),
            "username": os.environ.get("OS_USERNAME"),
            "password": os.environ.get("OS_PASSWORD"),
            "user_domain_name": os.environ.get("OS_USER_DOMAIN_NAME", "default"),
            "project_domain_name": os.environ.get("OS_PROJECT_DOMAIN_NAME", "default"),
        }
    elif auth_args is not None:
        # Use cloud configuration from clouds.yaml
        try:
            conn = connection.from_config(cloud=auth_args)
            return conn
        except exceptions.SDKException as e:
            raise CommandExecutionError(
                f"Failed to connect to OpenStack with cloud config {auth_args}: {str(e)}"
            )

    try:
        conn = connection.Connection(**auth_args)
        return conn
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to connect to OpenStack: {str(e)}")


def get_projects(auth_args=None):
    """
    List all projects in OpenStack

    Args:
        auth_args (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        list: List of project details

    CLI Example:

    .. code-block:: bash

        salt '*' openstack.get_projects
    """
    conn = _get_connection(auth_args)
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


def get_roles(auth_args=None):
    """
    List all roles in OpenStack

    Args:
        auth_args (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        list: List of role details

    CLI Example:

    .. code-block:: bash

        salt '*' openstack.get_roles
    """
    conn = _get_connection(auth_args)
    try:
        roles = [{"id": role.id, "name": role.name} for role in conn.identity.roles()]
        return roles
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to list roles: {str(e)}")
    finally:
        conn.close()


def get_groups(auth_args=None):
    """
    List all groups in OpenStack

    Args:
        auth_args (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        list: List of group details

    CLI Example:

    .. code-block:: bash

        salt '*' openstack.get_groups
    """
    conn = _get_connection(auth_args)
    try:
        groups = [
            {"id": group.id, "name": group.name} for group in conn.identity.groups()
        ]
        return groups
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to list groups: {str(e)}")
    finally:
        conn.close()


def create_project(name, description=None, domain_id="default", auth_args=None):
    """
    Create a new project in OpenStack

    Args:
        name (str): Name of the project
        description (str): Description of the project (optional)
        domain_id (str): Domain ID for the project (default is 'default')
        auth_args (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict: Information about the created project

    CLI Example:

    .. code-block:: bash

        salt '*' openstack.create_project myproject "My Project Description"
    """
    conn = _get_connection(auth_args)
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


def delete_project(name_or_id, auth_args=None):
    """
    Delete a project in OpenStack

    Args:
        name_or_id (str): Name or ID of the project to delete
        auth_args (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        bool: True if deletion was successful

    CLI Example:

    .. code-block:: bash

        salt '*' openstack.delete_project myproject
    """
    conn = _get_connection(auth_args)
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
    auth_args=None,
):
    """
    Assign a role to a group, optionally scoped to a project or domain

    Args:
        role_name_or_id (str): Name or ID of the role
        group_name_or_id (str): Name or ID of the group
        project_name_or_id (str): Name or ID of the project (optional)
        domain_name_or_id (str): Name or ID of the domain (optional)
        auth_args (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        bool: True if assignment was successful

    CLI Example:

    .. code-block:: bash

        salt '*' openstack.assign_role_to_group member mygroup myproject
    """
    conn = _get_connection(auth_args)
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
    auth_args=None,
):
    """
    Revoke a role from a group, scoped to a project or domain

    Args:
        role_name_or_id (str): Name or ID of the role
        group_name_or_id (str): Name or ID of the group
        project_name_or_id (str): Name or ID of the project (optional)
        domain_name_or_id (str): Name or ID of the domain (optional)
        auth_args (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        bool: True if revocation was successful

    CLI Example:

    .. code-block:: bash

        salt '*' openstack.revoke_role_from_group member mygroup myproject
    """
    conn = _get_connection(auth_args)
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
