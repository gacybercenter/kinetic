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
import time

from salt.exceptions import CommandExecutionError

__virtualname__ = "kinetic_openstack"

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


def _get_domain_id(conn, domain_name_or_id):
    """
    Helper function to resolve a domain name to its ID.

    Args:
        conn: OpenStack connection object
        domain_name_or_id (str): Domain name or ID

    Returns:
        str: Domain ID, or None if not found
    """
    try:
        domain = conn.identity.find_domain(domain_name_or_id)
        if domain:
            return domain.id
        return None
    except exceptions.SDKException:
        return None


def _diagnose_role_assignment(
    conn,
    role_name,
    group_name,
    project_name=None,
    domain_name=None,
    group_domain=None,
    project_domain=None,
):
    """
    Diagnostic function to verify all resources exist before attempting role assignment.

    Returns a dict with diagnostic information.
    """
    diagnostic = {
        "role": None,
        "group": None,
        "project": None,
        "domain": None,
        "errors": [],
    }

    try:
        # Check role
        role = conn.identity.find_role(role_name)
        if role:
            diagnostic["role"] = {"name": role.name, "id": role.id}
        else:
            diagnostic["errors"].append(f"Role '{role_name}' not found")

        # Check group
        if group_domain:
            domain_id = _get_domain_id(conn, group_domain)
            if not domain_id:
                diagnostic["errors"].append(f"Group domain '{group_domain}' not found")
            else:
                group = conn.identity.find_group(group_name, domain_id=domain_id)
                if group:
                    diagnostic["group"] = {
                        "name": group.name,
                        "id": group.id,
                        "domain": group_domain,
                    }
                else:
                    diagnostic["errors"].append(
                        f"Group '{group_name}' not found in domain '{group_domain}'"
                    )
        else:
            group = conn.identity.find_group(group_name)
            if group:
                diagnostic["group"] = {"name": group.name, "id": group.id}
            else:
                diagnostic["errors"].append(f"Group '{group_name}' not found")

        # Check project if specified
        if project_name:
            if project_domain:
                domain_id = _get_domain_id(conn, project_domain)
                if not domain_id:
                    diagnostic["errors"].append(
                        f"Project domain '{project_domain}' not found"
                    )
                else:
                    project = conn.identity.find_project(
                        project_name, domain_id=domain_id
                    )
                    if project:
                        diagnostic["project"] = {
                            "name": project.name,
                            "id": project.id,
                            "domain": project_domain,
                        }
                    else:
                        diagnostic["errors"].append(
                            f"Project '{project_name}' not found in domain '{project_domain}'"
                        )
            else:
                project = conn.identity.find_project(project_name)
                if project:
                    diagnostic["project"] = {"name": project.name, "id": project.id}
                else:
                    diagnostic["errors"].append(f"Project '{project_name}' not found")

        # Check domain if specified
        if domain_name:
            domain = conn.identity.find_domain(domain_name)
            if domain:
                diagnostic["domain"] = {"name": domain.name, "id": domain.id}
            else:
                diagnostic["errors"].append(f"Domain '{domain_name}' not found")

        return diagnostic
    except Exception as e:
        diagnostic["errors"].append(f"Error during diagnosis: {str(e)}")
        return diagnostic


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
            {
                "id": project.id,
                "name": project.name,
                "description": getattr(project, "description", None),
                "is_enabled": project.is_enabled,
                "domain_id": getattr(project, "domain_id", None),
            }
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


def get_group(group_name, domain_id=None, cloud=None):
    """
    Look up a single Keystone group by name, optionally scoped to a domain.

    Args:
        group_name (str): Name of the group.
        domain_id (str, optional): Domain ID to scope the lookup to.
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict or None

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.get_group admins domain_id=default cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        if domain_id:
            group = conn.identity.find_group(
                group_name, domain_id=domain_id, ignore_missing=True
            )
        else:
            group = conn.identity.find_group(group_name, ignore_missing=True)
        if not group:
            return None
        return {
            "id": group.id,
            "name": group.name,
            "domain_id": getattr(group, "domain_id", None),
            "description": getattr(group, "description", None),
        }
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to get group {group_name}: {str(e)}")
    finally:
        conn.close()


def create_group(group_name, domain_id=None, description=None, cloud=None):
    """
    Create a Keystone group (SQL-backed - i.e. NOT within a domain that uses
    a domain-specific LDAP identity driver).

    Args:
        group_name (str): Name of the group to create.
        domain_id (str, optional): Domain ID to create the group in.
        description (str, optional): Description of the group.
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.create_group admins domain_id=default cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        attrs = {"name": group_name}
        if domain_id is not None:
            attrs["domain_id"] = domain_id
        if description is not None:
            attrs["description"] = description
        group = conn.identity.create_group(**attrs)
        return {
            "id": group.id,
            "name": group.name,
            "domain_id": getattr(group, "domain_id", None),
            "description": getattr(group, "description", None),
        }
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to create group {group_name}: {str(e)}")
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
        dict: Updated project information including changes made, or None if no cloud configuration is provided

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.update_project myproject description="Updated description" is_enabled=True
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        project = conn.identity.find_project(name_or_id)
        if not project:
            raise CommandExecutionError(f"Project {name_or_id} not found")

        # Store original values for comparison
        original_values = {
            "description": project.description,
            "is_enabled": project.is_enabled,
        }

        updated_project = conn.identity.update_project(project, **updates)

        # Check what actually changed
        changes = {}
        for key, new_value in updates.items():
            if key in original_values and original_values[key] != new_value:
                changes[key] = {"old": original_values[key], "new": new_value}

        return {
            "id": updated_project.id,
            "name": updated_project.name,
            "description": updated_project.description,
            "domain_id": updated_project.domain_id,
            "is_enabled": updated_project.is_enabled,
            "changes": changes,
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
    group_domain=None,
    project_domain=None,
    cloud=None,
):
    """
    Assign a role to a group, optionally scoped to a project or domain

    Args:
        role_name_or_id (str): Name or ID of the role
        group_name_or_id (str): Name or ID of the group
        project_name_or_id (str): Name or ID of the project (optional)
        domain_name_or_id (str): Name or ID of the domain (optional)
        group_domain (str): Domain of the group (optional)
        project_domain (str): Domain of the project (optional)
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

        if group_domain:
            domain_id = _get_domain_id(conn, group_domain)
            if not domain_id:
                raise CommandExecutionError(f"Domain {group_domain} not found")
            group = conn.identity.find_group(group_name_or_id, domain_id=domain_id)
        else:
            group = conn.identity.find_group(group_name_or_id)
        if not group:
            raise CommandExecutionError(
                f"Group {group_name_or_id} not found in domain {group_domain if group_domain else 'default'}"
            )

        if project_name_or_id:
            if project_domain:
                domain_id = _get_domain_id(conn, project_domain)
                if not domain_id:
                    raise CommandExecutionError(f"Domain {project_domain} not found")
                project = conn.identity.find_project(
                    project_name_or_id, domain_id=domain_id
                )
            else:
                project = conn.identity.find_project(project_name_or_id)
            if not project:
                raise CommandExecutionError(
                    f"Project {project_name_or_id} not found in domain {project_domain if project_domain else 'default'}"
                )
            # Use Keystone REST API directly for role assignment
            endpoint = conn.session.get_endpoint(
                service_type="identity", interface="public"
            )
            url = f"{endpoint}/projects/{project.id}/groups/{group.id}/roles/{role.id}"
            log.debug(
                f"Assigning role to group on project - Project ID: {project.id}, Group ID: {group.id}, Role ID: {role.id}"
            )
            # Try multiple endpoint formats to find the correct one
            endpoints_to_try = [
                url,
                f"{endpoint.rstrip('/')}/v3/projects/{project.id}/groups/{group.id}/roles/{role.id}",
            ]

            success = False
            last_error = None
            for attempt_url in endpoints_to_try:
                try:
                    log.debug(f"Attempting role assignment with URL: {attempt_url}")
                    response = conn.session.put(attempt_url)
                    log.debug(
                        f"Role assignment response status: {response.status_code}, body: {response.text[:200] if response.text else 'empty'}"
                    )
                    if response.status_code in [201, 204]:
                        success = True
                        break
                    else:
                        last_error = f"HTTP {response.status_code}: {response.text[:200] if response.text else 'no response body'}"
                except Exception as e:
                    last_error = str(e)

            if not success:
                raise CommandExecutionError(
                    f"Failed to assign role {role.name} to group {group.name} on project {project.name}. "
                    f"Project ID: {project.id}, Group ID: {group.id}, Role ID: {role.id}. Error: {last_error}"
                )
        elif domain_name_or_id:
            domain = conn.identity.find_domain(domain_name_or_id)
            if not domain:
                raise CommandExecutionError(f"Domain {domain_name_or_id} not found")
            # Use Keystone REST API directly for role assignment
            endpoint = conn.session.get_endpoint(
                service_type="identity", interface="public"
            )
            url = f"{endpoint}/domains/{domain.id}/groups/{group.id}/roles/{role.id}"
            log.debug(
                f"Assigning role to group on domain - Domain ID: {domain.id}, Group ID: {group.id}, Role ID: {role.id}"
            )
            # Try multiple endpoint formats to find the correct one
            endpoints_to_try = [
                url,
                f"{endpoint.rstrip('/')}/v3/domains/{domain.id}/groups/{group.id}/roles/{role.id}",
            ]

            success = False
            last_error = None
            for attempt_url in endpoints_to_try:
                try:
                    log.debug(f"Attempting role assignment with URL: {attempt_url}")
                    response = conn.session.put(attempt_url)
                    log.debug(
                        f"Role assignment response status: {response.status_code}, body: {response.text[:200] if response.text else 'empty'}"
                    )
                    if response.status_code in [201, 204]:
                        success = True
                        break
                    else:
                        last_error = f"HTTP {response.status_code}: {response.text[:200] if response.text else 'no response body'}"
                except Exception as e:
                    last_error = str(e)

            if not success:
                raise CommandExecutionError(
                    f"Failed to assign role {role.name} to group {group.name} on domain {domain.name}. "
                    f"Domain ID: {domain.id}, Group ID: {group.id}, Role ID: {role.id}. Error: {last_error}"
                )
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
    group_domain=None,
    project_domain=None,
    cloud=None,
):
    """
    Revoke a role from a group, scoped to a project or domain

    Args:
        role_name_or_id (str): Name or ID of the role
        group_name_or_id (str): Name or ID of the group
        project_name_or_id (str): Name or ID of the project (optional)
        domain_name_or_id (str): Name or ID of the domain (optional)
        group_domain (str): Domain of the group (optional)
        project_domain (str): Domain of the project (optional)
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

        if group_domain:
            domain_id = _get_domain_id(conn, group_domain)
            if not domain_id:
                raise CommandExecutionError(f"Domain {group_domain} not found")
            group = conn.identity.find_group(group_name_or_id, domain_id=domain_id)
        else:
            group = conn.identity.find_group(group_name_or_id)
        if not group:
            raise CommandExecutionError(
                f"Group {group_name_or_id} not found in domain {group_domain if group_domain else 'default'}"
            )

        if project_name_or_id:
            if project_domain:
                domain_id = _get_domain_id(conn, project_domain)
                if not domain_id:
                    raise CommandExecutionError(f"Domain {project_domain} not found")
                project = conn.identity.find_project(
                    project_name_or_id, domain_id=domain_id
                )
            else:
                project = conn.identity.find_project(project_name_or_id)
            if not project:
                raise CommandExecutionError(
                    f"Project {project_name_or_id} not found in domain {project_domain if project_domain else 'default'}"
                )
            # Use Keystone REST API directly for role revocation
            endpoint = conn.session.get_endpoint(
                service_type="identity", interface="public"
            )
            url = f"{endpoint}/projects/{project.id}/groups/{group.id}/roles/{role.id}"
            log.debug(
                f"Revoking role from group on project - Project ID: {project.id}, Group ID: {group.id}, Role ID: {role.id}"
            )
            # Try multiple endpoint formats to find the correct one
            endpoints_to_try = [
                url,
                f"{endpoint.rstrip('/')}/v3/projects/{project.id}/groups/{group.id}/roles/{role.id}",
            ]

            success = False
            last_error = None
            for attempt_url in endpoints_to_try:
                try:
                    log.debug(f"Attempting role revocation with URL: {attempt_url}")
                    response = conn.session.delete(attempt_url)
                    log.debug(
                        f"Role revocation response status: {response.status_code}, body: {response.text[:200] if response.text else 'empty'}"
                    )
                    if response.status_code in [204, 404]:
                        success = True
                        break
                    else:
                        last_error = f"HTTP {response.status_code}: {response.text[:200] if response.text else 'no response body'}"
                except Exception as e:
                    last_error = str(e)

            if not success:
                raise CommandExecutionError(
                    f"Failed to revoke role {role.name} from group {group.name} on project {project.name}. "
                    f"Project ID: {project.id}, Group ID: {group.id}, Role ID: {role.id}. Error: {last_error}"
                )
        elif domain_name_or_id:
            domain = conn.identity.find_domain(domain_name_or_id)
            if not domain:
                raise CommandExecutionError(f"Domain {domain_name_or_id} not found")
            # Use Keystone REST API directly for role revocation
            endpoint = conn.session.get_endpoint(
                service_type="identity", interface="public"
            )
            url = f"{endpoint}/domains/{domain.id}/groups/{group.id}/roles/{role.id}"
            log.debug(
                f"Revoking role from group on domain - Domain ID: {domain.id}, Group ID: {group.id}, Role ID: {role.id}"
            )
            # Try multiple endpoint formats to find the correct one
            endpoints_to_try = [
                url,
                f"{endpoint.rstrip('/')}/v3/domains/{domain.id}/groups/{group.id}/roles/{role.id}",
            ]

            success = False
            last_error = None
            for attempt_url in endpoints_to_try:
                try:
                    log.debug(f"Attempting role revocation with URL: {attempt_url}")
                    response = conn.session.delete(attempt_url)
                    log.debug(
                        f"Role revocation response status: {response.status_code}, body: {response.text[:200] if response.text else 'empty'}"
                    )
                    if response.status_code in [204, 404]:
                        success = True
                        break
                    else:
                        last_error = f"HTTP {response.status_code}: {response.text[:200] if response.text else 'no response body'}"
                except Exception as e:
                    last_error = str(e)

            if not success:
                raise CommandExecutionError(
                    f"Failed to revoke role {role.name} from group {group.name} on domain {domain.name}. "
                    f"Domain ID: {domain.id}, Group ID: {group.id}, Role ID: {role.id}. Error: {last_error}"
                )
        else:
            raise CommandExecutionError(
                "Either project or domain must be specified for role revocation"
            )

        return True
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to revoke role: {str(e)}")
    finally:
        conn.close()


def test_role_assignment_api(
    role_name,
    group_name,
    project_name=None,
    domain_name=None,
    group_domain=None,
    project_domain=None,
    cloud=None,
):
    """
    Test the role assignment API endpoint to determine which URL format works.

    This function attempts to make a test PUT request to various API endpoint
    formats to diagnose which one is correct for your Keystone installation.

    Args:
        role_name (str): Name of the role
        group_name (str): Name of the group
        project_name (str, optional): Name of the project
        domain_name (str, optional): Name of the domain
        group_domain (str, optional): Domain of the group
        project_domain (str, optional): Domain of the project
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict: Test results showing which endpoints work/fail

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.test_role_assignment_api role_name=member group_name=interns project_name=interns project_domain=Default group_domain=ldap cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return {
            "error": "Failed to connect to OpenStack",
            "results": None,
        }

    try:
        # First get all the IDs
        diagnostic = _diagnose_role_assignment(
            conn,
            role_name=role_name,
            group_name=group_name,
            project_name=project_name,
            domain_name=domain_name,
            group_domain=group_domain,
            project_domain=project_domain,
        )

        if diagnostic["errors"]:
            return {
                "success": False,
                "errors": diagnostic["errors"],
                "results": None,
            }

        role = diagnostic["role"]
        group = diagnostic["group"]
        project = diagnostic["project"]

        if not (role and group and project):
            return {
                "success": False,
                "error": "Missing required resources",
                "diagnostic": diagnostic,
                "results": None,
            }

        # Get the endpoint
        endpoint = conn.session.get_endpoint(
            service_type="identity", interface="public"
        )

        # Test various URL formats
        test_urls = [
            f"{endpoint}/projects/{project['id']}/groups/{group['id']}/roles/{role['id']}",
            f"{endpoint.rstrip('/')}/projects/{project['id']}/groups/{group['id']}/roles/{role['id']}",
            f"{endpoint}/projects/{project['id']}/groups/{group['id']}/roles/{role['id']}/",
            f"{endpoint.rstrip('/')}/projects/{project['id']}/groups/{group['id']}/roles/{role['id']}/",
        ]

        results = {
            "endpoint": endpoint,
            "role_id": role["id"],
            "group_id": group["id"],
            "project_id": project["id"],
            "tests": [],
        }

        for url in test_urls:
            test_result = {
                "url": url,
                "method": "PUT",
                "status": None,
                "response": None,
            }
            try:
                # Make a test PUT request (note: we're actually making it, not just testing)
                response = conn.session.put(url)
                test_result["status"] = response.status_code
                test_result["response"] = (
                    response.text[:500] if response.text else "empty"
                )
                test_result["success"] = response.status_code in [201, 204]
            except Exception as e:
                test_result["error"] = str(e)
                test_result["success"] = False

            results["tests"].append(test_result)

        return {
            "success": any(t.get("success", False) for t in results["tests"]),
            "results": results,
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "results": None,
        }
    finally:
        conn.close()


def check_role_assignment(
    role_name, project_name_or_id, group_name=None, user_name=None, cloud=None
):
    """
    Check if role assignment exists.

    Returns:
        bool
    """
    conn = _get_connection(cloud)
    if conn is None:
        return False
    try:
        role = conn.identity.find_role(role_name)
        if not role:
            return False
        project = conn.identity.find_project(project_name_or_id)
        if not project:
            return False
        if group_name:
            group = conn.identity.find_group(group_name)
            if not group:
                return False
            it = conn.identity.role_assignments(
                role=role.id, group=group.id, project=project.id
            )
        elif user_name:
            user = conn.identity.find_user(user_name)
            if not user:
                return False
            it = conn.identity.role_assignments(
                role=role.id, user=user.id, project=project.id
            )
        else:
            return False
        try:
            next(it)
            return True
        except StopIteration:
            return False
    except exceptions.SDKException:
        return False
    finally:
        conn.close()


def diagnose_role_assignment(
    role_name,
    group_name,
    project_name=None,
    domain_name=None,
    group_domain=None,
    project_domain=None,
    cloud=None,
):
    """
    Diagnose role assignment prerequisites - check if all required resources exist.

    This function helps troubleshoot why role assignments might be failing by verifying
    that all the resources (role, group, project, domain) exist and are accessible.

    Args:
        role_name (str): Name of the role
        group_name (str): Name of the group
        project_name (str, optional): Name of the project
        domain_name (str, optional): Name of the domain
        group_domain (str, optional): Domain of the group
        project_domain (str, optional): Domain of the project
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict: Diagnostic information with keys: role, group, project, domain, errors

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.diagnose_role_assignment role_name=member group_name=interns project_name=example project_domain=Default group_domain=ldap
    """
    conn = _get_connection(cloud)
    if conn is None:
        return {
            "error": "Failed to connect to OpenStack",
            "diagnostic": None,
        }

    try:
        diagnostic = _diagnose_role_assignment(
            conn,
            role_name=role_name,
            group_name=group_name,
            project_name=project_name,
            domain_name=domain_name,
            group_domain=group_domain,
            project_domain=project_domain,
        )
        return {"success": len(diagnostic["errors"]) == 0, "diagnostic": diagnostic}
    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "diagnostic": None,
        }
    finally:
        conn.close()


def check_health(cloud=None, timeout=180, interval=5):
    """
    Poll the Keystone identity API until it responds successfully or the
    timeout is reached. Intended as a gate before running federation setup:
    a Helm release reporting "deployed" does not guarantee the external
    Ingress/HTTPRoute/DNS path to Keystone is actually ready yet.

    Args:
        cloud (str): Name of the cloud configuration from clouds.yaml
        timeout (int): Maximum time in seconds to wait for Keystone to respond
        interval (int): Seconds to wait between retries

    Returns:
        dict: {"success": bool, "healthy": bool, "message": str}

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.check_health cloud=rsc timeout=180 interval=5
    """
    if cloud is None:
        return {
            "success": False,
            "healthy": False,
            "message": "No cloud configuration name provided.",
        }

    last_error = None
    elapsed = 0
    while True:
        conn = None
        try:
            conn = connection.from_config(cloud=cloud)
            conn.authorize()
            return {
                "success": True,
                "healthy": True,
                "message": "Keystone is reachable and issuing tokens.",
            }
        except Exception as e:
            last_error = str(e)
        finally:
            if conn is not None:
                conn.close()

        if elapsed >= timeout:
            break
        time.sleep(min(interval, timeout - elapsed))
        elapsed += interval

    return {
        "success": False,
        "healthy": False,
        "message": f"Keystone did not become healthy within {timeout}s: {last_error}",
    }


def get_domain(domain_name_or_id, cloud=None):
    """
    Look up an existing Keystone domain by name or ID. Never creates one.

    Args:
        domain_name_or_id (str): Name or ID of the domain.
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict or None: {"id": ..., "name": ...} or None if not found.

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.get_domain rsc cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        domain = conn.identity.find_domain(domain_name_or_id)
        if not domain:
            return None
        return {"id": domain.id, "name": domain.name}
    except exceptions.SDKException as e:
        raise CommandExecutionError(
            f"Failed to look up domain {domain_name_or_id}: {str(e)}"
        )
    finally:
        conn.close()


def get_identity_provider(idp_id, cloud=None):
    """
    Get a single OS-FEDERATION identity provider by ID.

    Args:
        idp_id (str): The identity provider ID.
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict or None

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.get_identity_provider keycloak cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        idp = conn.identity.find_identity_provider(idp_id, ignore_missing=True)
        if not idp:
            return None
        return {
            "id": idp.id,
            "domain_id": idp.domain_id,
            "description": idp.description,
            "enabled": idp.is_enabled,
            "remote_ids": idp.remote_ids or [],
        }
    except exceptions.SDKException as e:
        raise CommandExecutionError(
            f"Failed to get identity provider {idp_id}: {str(e)}"
        )
    finally:
        conn.close()


def create_identity_provider(
    idp_id,
    domain_id=None,
    description=None,
    enabled=True,
    remote_ids=None,
    cloud=None,
):
    """
    Create an OS-FEDERATION identity provider.

    Args:
        idp_id (str): The identity provider ID.
        domain_id (str): ID of the (existing) domain to scope the IdP to.
        description (str, optional): Description of the identity provider.
        enabled (bool, optional): Whether the identity provider is enabled. Defaults to True.
        remote_ids (list, optional): List of remote IdP issuer URLs.
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.create_identity_provider keycloak domain_id=abc123 remote_ids='["https://keycloak.example.com/realms/rsc"]' cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        # openstacksdk's IdentityProvider resource exposes this as
        # is_enabled (the REST API's wire-format key is "enabled", but the
        # Python attribute/constructor kwarg is is_enabled).
        attrs = {"is_enabled": enabled, "remote_ids": remote_ids or []}
        if domain_id is not None:
            attrs["domain_id"] = domain_id
        if description is not None:
            attrs["description"] = description
        idp = conn.identity.create_identity_provider(id=idp_id, **attrs)
        return {
            "id": idp.id,
            "domain_id": idp.domain_id,
            "description": idp.description,
            "enabled": idp.is_enabled,
            "remote_ids": idp.remote_ids or [],
        }
    except exceptions.SDKException as e:
        raise CommandExecutionError(
            f"Failed to create identity provider {idp_id}: {str(e)}"
        )
    finally:
        conn.close()


def update_identity_provider(idp_id, cloud=None, **attrs):
    """
    Update an existing OS-FEDERATION identity provider.

    Args:
        idp_id (str): The identity provider ID.
        cloud (str): Optional name of the cloud configuration from clouds.yaml
        **attrs: Attributes to update (e.g. enabled, description, remote_ids, domain_id).

    Returns:
        dict

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.update_identity_provider keycloak enabled=True cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        idp = conn.identity.find_identity_provider(idp_id, ignore_missing=True)
        if not idp:
            raise CommandExecutionError(f"Identity provider {idp_id} not found")
        # See create_identity_provider: the SDK attribute/kwarg is
        # is_enabled, not enabled.
        if "enabled" in attrs:
            attrs["is_enabled"] = attrs.pop("enabled")
        idp = conn.identity.update_identity_provider(idp, **attrs)
        return {
            "id": idp.id,
            "domain_id": idp.domain_id,
            "description": idp.description,
            "enabled": idp.is_enabled,
            "remote_ids": idp.remote_ids or [],
        }
    except exceptions.SDKException as e:
        raise CommandExecutionError(
            f"Failed to update identity provider {idp_id}: {str(e)}"
        )
    finally:
        conn.close()


def get_mapping(mapping_id, cloud=None):
    """
    Get a single OS-FEDERATION mapping by ID.

    Args:
        mapping_id (str): The mapping ID.
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict or None

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.get_mapping keycloak_openid cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        m = conn.identity.find_mapping(mapping_id, ignore_missing=True)
        if not m:
            return None
        return {"id": m.id, "rules": m.rules}
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to get mapping {mapping_id}: {str(e)}")
    finally:
        conn.close()


def create_mapping(mapping_id, rules, cloud=None):
    """
    Create an OS-FEDERATION mapping.

    Args:
        mapping_id (str): The mapping ID.
        rules (list): List of mapping rule dicts (local/remote).
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.create_mapping keycloak_openid rules='[...]' cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        m = conn.identity.create_mapping(id=mapping_id, rules=rules)
        return {"id": m.id, "rules": m.rules}
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to create mapping {mapping_id}: {str(e)}")
    finally:
        conn.close()


def update_mapping(mapping_id, rules, cloud=None):
    """
    Update an existing OS-FEDERATION mapping's rules.

    Args:
        mapping_id (str): The mapping ID.
        rules (list): List of mapping rule dicts (local/remote).
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.update_mapping keycloak_openid rules='[...]' cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        m = conn.identity.find_mapping(mapping_id, ignore_missing=True)
        if not m:
            raise CommandExecutionError(f"Mapping {mapping_id} not found")
        m = conn.identity.update_mapping(m, rules=rules)
        return {"id": m.id, "rules": m.rules}
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to update mapping {mapping_id}: {str(e)}")
    finally:
        conn.close()


def get_federation_protocol(idp_id, protocol_id, cloud=None):
    """
    Get a single federation protocol registered on an identity provider.

    Args:
        idp_id (str): The identity provider ID.
        protocol_id (str): The protocol ID (e.g. "openid").
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict or None

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.get_federation_protocol keycloak openid cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        proto = conn.identity.find_federation_protocol(
            idp_id, protocol_id, ignore_missing=True
        )
        if not proto:
            return None
        return {"id": proto.id, "mapping_id": proto.mapping_id}
    except exceptions.SDKException as e:
        raise CommandExecutionError(
            f"Failed to get federation protocol {protocol_id} for idp {idp_id}: {str(e)}"
        )
    finally:
        conn.close()


def create_federation_protocol(idp_id, protocol_id, mapping_id, cloud=None):
    """
    Register a federation protocol on an identity provider.

    Args:
        idp_id (str): The identity provider ID.
        protocol_id (str): The protocol ID (e.g. "openid").
        mapping_id (str): The mapping ID to associate with this protocol.
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.create_federation_protocol keycloak openid keycloak_openid cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        proto = conn.identity.create_federation_protocol(
            idp_id, id=protocol_id, mapping_id=mapping_id
        )
        return {"id": proto.id, "mapping_id": proto.mapping_id}
    except exceptions.SDKException as e:
        raise CommandExecutionError(
            f"Failed to create federation protocol {protocol_id} for idp {idp_id}: {str(e)}"
        )
    finally:
        conn.close()


def update_federation_protocol(idp_id, protocol_id, mapping_id, cloud=None):
    """
    Update the mapping used by an existing federation protocol.

    Args:
        idp_id (str): The identity provider ID.
        protocol_id (str): The protocol ID (e.g. "openid").
        mapping_id (str): The mapping ID to associate with this protocol.
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.update_federation_protocol keycloak openid keycloak_openid cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        proto = conn.identity.find_federation_protocol(
            idp_id, protocol_id, ignore_missing=True
        )
        if not proto:
            raise CommandExecutionError(
                f"Federation protocol {protocol_id} for idp {idp_id} not found"
            )
        proto = conn.identity.update_federation_protocol(
            idp_id, proto, mapping_id=mapping_id
        )
        return {"id": proto.id, "mapping_id": proto.mapping_id}
    except exceptions.SDKException as e:
        raise CommandExecutionError(
            f"Failed to update federation protocol {protocol_id} for idp {idp_id}: {str(e)}"
        )
    finally:
        conn.close()


def get_service(name, cloud=None):
    """
    Look up a Keystone service catalog entry by name or ID.

    Args:
        name (str): The service name or ID (e.g. "swift").
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict or None

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.get_service swift cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        svc = conn.identity.find_service(name, ignore_missing=True)
        if not svc:
            return None
        return {
            "id": svc.id,
            "name": svc.name,
            "type": svc.type,
            "description": svc.description,
            "enabled": svc.is_enabled,
        }
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to get service {name}: {str(e)}")
    finally:
        conn.close()


def create_service(name, type, description=None, enabled=True, cloud=None):
    """
    Create a Keystone service catalog entry.

    Args:
        name (str): The service name (e.g. "swift").
        type (str): The service type (e.g. "object-store").
        description (str, optional): Description of the service.
        enabled (bool, optional): Whether the service is enabled. Defaults to True.
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.create_service swift object-store cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        attrs = {"name": name, "type": type, "is_enabled": enabled}
        if description is not None:
            attrs["description"] = description
        svc = conn.identity.create_service(**attrs)
        return {
            "id": svc.id,
            "name": svc.name,
            "type": svc.type,
            "description": svc.description,
            "enabled": svc.is_enabled,
        }
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to create service {name}: {str(e)}")
    finally:
        conn.close()


def update_service(name, cloud=None, **attrs):
    """
    Update an existing Keystone service catalog entry.

    Args:
        name (str): The service name or ID.
        cloud (str): Optional name of the cloud configuration from clouds.yaml
        **attrs: Attributes to update (e.g. type, description, enabled).

    Returns:
        dict

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.update_service swift description="Swift Object Storage" cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        svc = conn.identity.find_service(name, ignore_missing=True)
        if not svc:
            raise CommandExecutionError(f"Service {name} not found")
        # Service exposes the enabled flag as is_enabled, not enabled.
        if "enabled" in attrs:
            attrs["is_enabled"] = attrs.pop("enabled")
        svc = conn.identity.update_service(svc, **attrs)
        return {
            "id": svc.id,
            "name": svc.name,
            "type": svc.type,
            "description": svc.description,
            "enabled": svc.is_enabled,
        }
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to update service {name}: {str(e)}")
    finally:
        conn.close()


def get_endpoint(service_name, interface, region=None, cloud=None):
    """
    Look up a Keystone endpoint by service, interface, and (optionally) region.

    Args:
        service_name (str): The service name or ID (e.g. "swift").
        interface (str): One of "public", "internal", "admin".
        region (str, optional): Region ID to filter by.
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict or None

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.get_endpoint swift public region=default cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        svc = conn.identity.find_service(service_name, ignore_missing=True)
        if not svc:
            return None
        for ep in conn.identity.endpoints(service_id=svc.id, interface=interface):
            if region is not None and ep.region_id != region:
                continue
            return {
                "id": ep.id,
                "service_id": ep.service_id,
                "interface": ep.interface,
                "region_id": ep.region_id,
                "url": ep.url,
                "enabled": ep.is_enabled,
            }
        return None
    except exceptions.SDKException as e:
        raise CommandExecutionError(
            f"Failed to get endpoint for service {service_name} ({interface}): {str(e)}"
        )
    finally:
        conn.close()


def create_endpoint(service_name, interface, url, region=None, enabled=True, cloud=None):
    """
    Create a Keystone endpoint for a service.

    Args:
        service_name (str): The service name or ID (e.g. "swift").
        interface (str): One of "public", "internal", "admin".
        url (str): The endpoint URL.
        region (str, optional): Region ID (e.g. "default"). Keystone does not
            require a matching Region resource to already exist.
        enabled (bool, optional): Whether the endpoint is enabled. Defaults to True.
        cloud (str): Optional name of the cloud configuration from clouds.yaml

    Returns:
        dict

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.create_endpoint swift public https://swift.example.com/swift/v1 region=default cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        svc = conn.identity.find_service(service_name, ignore_missing=True)
        if not svc:
            raise CommandExecutionError(f"Service {service_name} not found")
        attrs = {
            "service_id": svc.id,
            "interface": interface,
            "url": url,
            "is_enabled": enabled,
        }
        if region is not None:
            attrs["region_id"] = region
        ep = conn.identity.create_endpoint(**attrs)
        return {
            "id": ep.id,
            "service_id": ep.service_id,
            "interface": ep.interface,
            "region_id": ep.region_id,
            "url": ep.url,
            "enabled": ep.is_enabled,
        }
    except exceptions.SDKException as e:
        raise CommandExecutionError(
            f"Failed to create endpoint for service {service_name} ({interface}): {str(e)}"
        )
    finally:
        conn.close()


def update_endpoint(endpoint_id, cloud=None, **attrs):
    """
    Update an existing Keystone endpoint.

    Args:
        endpoint_id (str): The endpoint ID.
        cloud (str): Optional name of the cloud configuration from clouds.yaml
        **attrs: Attributes to update (e.g. url, region (mapped to region_id), enabled).

    Returns:
        dict

    CLI Example:

    .. code-block:: bash

        salt '*' kinetic_openstack.update_endpoint <id> url=https://swift.example.com/swift/v1 cloud=rsc
    """
    conn = _get_connection(cloud)
    if conn is None:
        return None
    try:
        ep = conn.identity.find_endpoint(endpoint_id, ignore_missing=True)
        if not ep:
            raise CommandExecutionError(f"Endpoint {endpoint_id} not found")
        if "enabled" in attrs:
            attrs["is_enabled"] = attrs.pop("enabled")
        if "region" in attrs:
            attrs["region_id"] = attrs.pop("region")
        ep = conn.identity.update_endpoint(ep, **attrs)
        return {
            "id": ep.id,
            "service_id": ep.service_id,
            "interface": ep.interface,
            "region_id": ep.region_id,
            "url": ep.url,
            "enabled": ep.is_enabled,
        }
    except exceptions.SDKException as e:
        raise CommandExecutionError(f"Failed to update endpoint {endpoint_id}: {str(e)}")
    finally:
        conn.close()
