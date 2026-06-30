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
