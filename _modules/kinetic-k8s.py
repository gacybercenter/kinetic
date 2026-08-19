# -*- coding: utf-8 -*-
"""
SaltStack execution module for interacting with Kubernetes to retrieve hardware data.

This module provides functions to query Kubernetes Custom Resources, specifically
for retrieving MAC addresses from HardwareData resources in a Metal3.io environment.
"""

import base64
import inspect
import json

import salt.utils.decorators as decorators
from kubernetes import client, config
from kubernetes.client.rest import ApiException

# Ensure Salt can find this module
__virtualname__ = "kinetic_k8s"


@decorators.memoize
def __virtual__():
    """
    Check if the kubernetes python library is available.
    """
    try:
        from kubernetes import client

        return "kinetic_k8s"
    except ImportError:
        return (
            False,
            'The kubernetes python library is not installed. Please install it using "pip install kubernetes".',
        )


def _load_k8s_config():
    """Load Kubernetes configuration, preferring in-cluster config then kubeconfig."""
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()


def _render_salt_template(template_path, context, renderer="jinja|yaml"):
    """
    Load a Salt URI template, strip any shebang line, render it, and return the result.
    Raises Exception if the template is empty or rendering fails.
    """
    content = __salt__["cp.get_file_str"](template_path)
    if not content:
        raise Exception(f"Empty template at {template_path}")
    if content.startswith("#!"):
        lines = content.splitlines()
        content = "\n".join(lines[1:]) if len(lines) > 1 else ""
    rendered = __salt__["slsutil.renderer"](
        string=content, default_renderer=renderer, context=context
    )
    if not rendered:
        raise Exception(f"Failed to render template {template_path}")
    return rendered


def _decode_k8s_secret(secret):
    """
    Return a plain string-keyed dict from a Kubernetes secret object.
    Prefers string_data; falls back to base64-decoding the data field.
    """
    data = secret.string_data if secret.string_data else {}
    if not data and secret.data:
        data = {k: base64.b64decode(v).decode("utf-8") for k, v in secret.data.items()}
    return data


def handle_certmanager_resource_version(
    body,
    existing_resource=None,
    api_instance=None,
    group=None,
    version=None,
    namespace=None,
    plural=None,
    name=None,
):
    """
    Handle resourceVersion for cert-manager resource updates.
    Use the existing resource's resourceVersion if valid.
    If invalid (like '0') or missing, remove it from the body to mimic restore behavior.
    Optionally attempt to fetch the latest resource if api_instance details are provided.

    Args:
        body (dict): The resource body to update.
        existing_resource (dict, optional): The existing resource data if already fetched.
        api_instance (CustomObjectsApi, optional): API instance to fetch the resource if needed.
        group (str, optional): API group for fetching.
        version (str, optional): API version for fetching.
        namespace (str, optional): Namespace for fetching.
        plural (str, optional): Resource plural name for fetching.
        name (str, optional): Resource name for fetching.

    Returns:
        dict: The updated resource body with resourceVersion handled appropriately.
        str: A message indicating the status of resourceVersion handling.
    """
    message = ""
    if (
        existing_resource
        and "metadata" in existing_resource
        and "resourceVersion" in existing_resource["metadata"]
    ):
        resource_version = existing_resource["metadata"].get("resourceVersion", "")
        if resource_version and resource_version != "0":
            body.setdefault("metadata", {}).update(
                {"resourceVersion": resource_version}
            )
            message = "Using existing resourceVersion for update."
        else:
            if "metadata" in body:
                body["metadata"].pop("resourceVersion", None)
            message = "Existing resourceVersion is invalid or zero, removed for update."
    else:
        if "metadata" in body:
            body["metadata"].pop("resourceVersion", None)
        message = "No valid existing resource data, resourceVersion removed for update."

    # Optional: Attempt to fetch latest if resourceVersion was invalid or missing
    if message.startswith("Existing resourceVersion is invalid") or message.startswith(
        "No valid existing resource data"
    ):
        if api_instance and all([group, version, namespace, plural, name]):
            try:
                latest_resource = api_instance.get_namespaced_custom_object(
                    group, version, namespace, plural, name
                )
                if (
                    "metadata" in latest_resource
                    and "resourceVersion" in latest_resource["metadata"]
                ):
                    resource_version = latest_resource["metadata"].get(
                        "resourceVersion", ""
                    )
                    if resource_version and resource_version != "0":
                        body.setdefault("metadata", {}).update(
                            {"resourceVersion": resource_version}
                        )
                        message = "Fetched latest resourceVersion for update."
            except Exception as e:
                message += f" Failed to fetch latest resourceVersion: {str(e)[:50]}..."
    return body, message


def get_mac_by_interface_name(namespace, resource_name, interface_name):
    """
    Retrieve the MAC address of a network interface from a HardwareData Custom Resource in Kubernetes.

    Args:
        namespace (str): The namespace of the HardwareData resource.
        resource_name (str): The name of the HardwareData resource.
        interface_name (str): The name of the network interface to query.

    Returns:
        dict: A dictionary with 'success' (bool), 'mac' (str if found), and 'message' (str for status or error).

    CLI Example:
        salt '*' kubernetes_k8s.get_mac_by_interface_name baremetal-operator-system compute-133-26 enp97s0f0
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "metal3.io"
        version = "v1alpha1"
        plural = "hardwaredata"

        resource = custom_api.get_namespaced_custom_object(
            group=group,
            version=version,
            namespace=namespace,
            plural=plural,
            name=resource_name,
        )

        nics = resource.get("spec", {}).get("hardware", {}).get("nics", [])
        for nic in nics:
            if nic.get("name") == interface_name:
                return {
                    "success": True,
                    "mac": nic.get("mac", ""),
                    "message": f"Found MAC for {interface_name}",
                }

        return {
            "success": False,
            "mac": "",
            "message": f"Interface {interface_name} not found",
        }

    except ApiException as e:
        return {
            "success": False,
            "mac": "",
            "message": f"Kubernetes API error: {str(e)[:50]}...",
        }
    except Exception as e:
        return {"success": False, "mac": "", "message": f"Error: {str(e)[:50]}..."}


def get_all_interfaces(namespace, resource_name):
    """
    Retrieve all network interfaces and their MAC addresses from a HardwareData Custom Resource.

    Args:
        namespace (str): The namespace of the HardwareData resource.
        resource_name (str): The name of the HardwareData resource.

    Returns:
        dict: A dictionary with 'success' (bool), 'interfaces' (dict of interface name to MAC), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.get_all_interfaces baremetal-operator-system compute-133-26
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "metal3.io"
        version = "v1alpha1"
        plural = "hardwaredata"

        resource = custom_api.get_namespaced_custom_object(
            group=group,
            version=version,
            namespace=namespace,
            plural=plural,
            name=resource_name,
        )

        nics = resource.get("spec", {}).get("hardware", {}).get("nics", [])
        interfaces = {
            nic.get("name"): nic.get("mac")
            for nic in nics
            if nic.get("name") and nic.get("mac")
        }

        return {
            "success": True,
            "interfaces": interfaces,
            "message": f"Retrieved {len(interfaces)} interfaces",
        }

    except ApiException as e:
        return {
            "success": False,
            "interfaces": {},
            "message": f"Kubernetes API error: {str(e)[:50]}...",
        }
    except Exception as e:
        return {
            "success": False,
            "interfaces": {},
            "message": f"Error: {str(e)[:50]}...",
        }


def bmh_present(
    namespace,
    bmh_name,
    pillar_data,
    bmh_template_path="salt://formulas/bmo/files/bmh.j2",
):
    """
    Ensure that the Bare Metal Host (BMH) object in Kubernetes matches the desired state
    defined by pillar data and Jinja2 template. Updates BMH if possible, or deletes and recreates
    if it needs updating and is in an error state.

    Args:
        namespace (str): The namespace of the Bare Metal Host resource in Kubernetes.
        bmh_name (str): The name of the Bare Metal Host resource.
        pillar_data (dict): Pillar data containing the desired BMH configuration.
        bmh_template_path (str, optional): Salt URI to the Jinja2 template file for BMH.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'recreated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.bmh_present baremetal-operator-system compute-133-26 pillar_data
    """
    try:
        updated = False
        recreated = False
        exists = False
        matches = False
        in_error_state = False
        differences = {}

        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "metal3.io"
        version = "v1alpha1"
        plural = "baremetalhosts"

        # Check if BMH exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=bmh_name,
            )
            exists = True
            current_bmh = resource.get("spec", {})
            status = resource.get("status", {})
            in_error_state = (
                status.get("errorMessage", "") != ""
                or status.get("provisioning", {}).get("state", "") == "error"
            )
        except ApiException:
            exists = False
            current_bmh = {}
        except Exception as e:
            exists = False
            current_bmh = {}
            return {
                "success": False,
                "updated": False,
                "recreated": False,
                "message": f"Error fetching BMH: {str(e)[:50]}...",
            }

        # Render desired BMH configuration
        try:
            network_data_name = f"{bmh_name}-network-data"
            userdata_name = f"{bmh_name}-user-data"
            bmc_auth_name = f"{bmh_name}-bmc-auth"
            bmh_context = {
                "name": bmh_name,
                "namespace": namespace,
                "online": pillar_data.get("online", False),
                "address": pillar_data.get("bmc", {}).get("address", ""),
                "credentialsName": bmc_auth_name,
                "bootMACAddress": pillar_data.get("bootMACAddress", ""),
                "checksum": pillar_data.get("image", {}).get("checksum", ""),
                "format": pillar_data.get("image", {}).get("format", ""),
                "url": pillar_data.get("image", {}).get("url", ""),
                "rootdevice": pillar_data.get("rootDeviceHints", {}).get(
                    "deviceName", ""
                ),
                "networkdata": network_data_name if "network" in pillar_data else "",
                "userdata": userdata_name if "network" in pillar_data else "",
            }

            rendered_bmh = _render_salt_template(bmh_template_path, bmh_context)

            import yaml

            desired_bmh = (
                rendered_bmh
                if isinstance(rendered_bmh, dict)
                else yaml.safe_load(rendered_bmh)
            )

            if exists:
                current_spec = current_bmh
                desired_spec = desired_bmh.get("spec", {})
                for key in desired_spec:
                    if (
                        key not in current_spec
                        or current_spec[key] != desired_spec[key]
                    ):
                        differences[key] = {"desired": desired_spec[key]}
                matches = len(differences) == 0
            else:
                matches = False
        except Exception as e:
            return {
                "success": False,
                "updated": False,
                "recreated": False,
                "message": f"BMH template render failed: {str(e)[:50]}...",
            }

        # Update or create BMH only if necessary
        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=desired_bmh,
                )
                updated = True
                recreated = True
                message = f"BMH {bmh_name} created"
            except ApiException as e:
                updated = False
                recreated = False
                message = f"BMH {bmh_name} creation failed: {str(e)[:50]}..."
        elif not matches or in_error_state:
            try:
                body = desired_bmh
                if (
                    exists
                    and "metadata" in resource
                    and "resourceVersion" in resource["metadata"]
                ):
                    body.setdefault("metadata", {}).update(
                        {
                            "resourceVersion": resource["metadata"].get(
                                "resourceVersion", ""
                            )
                        }
                    )
                try:
                    custom_api.replace_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        name=bmh_name,
                        body=body,
                    )
                    updated = True
                    recreated = False
                    message = f"BMH {bmh_name} updated"
                except ApiException as update_error:
                    if in_error_state:
                        import time

                        custom_api.delete_namespaced_custom_object(
                            group=group,
                            version=version,
                            namespace=namespace,
                            plural=plural,
                            name=bmh_name,
                            body=client.V1DeleteOptions(
                                propagation_policy="Foreground", grace_period_seconds=5
                            ),
                        )
                        wait_time = 0
                        max_wait = 60
                        wait_interval = 5
                        while wait_time < max_wait:
                            try:
                                custom_api.get_namespaced_custom_object(
                                    group=group,
                                    version=version,
                                    namespace=namespace,
                                    plural=plural,
                                    name=bmh_name,
                                )
                                time.sleep(wait_interval)
                                wait_time += wait_interval
                            except ApiException as get_error:
                                if get_error.status == 404:
                                    break
                                else:
                                    message = f"BMH {bmh_name} deletion check failed: {str(get_error)[:50]}..."
                                    break
                        custom_api.create_namespaced_custom_object(
                            group=group,
                            version=version,
                            namespace=namespace,
                            plural=plural,
                            body=body,
                        )
                        updated = True
                        recreated = True
                        message = f"BMH {bmh_name} recreated"
                    else:
                        updated = False
                        recreated = False
                        message = (
                            f"BMH {bmh_name} update failed: {str(update_error)[:50]}..."
                        )
            except ApiException as e:
                updated = False
                recreated = False
                message = f"BMH {bmh_name} operation failed: {str(e)[:50]}..."
        else:
            message = f"BMH {bmh_name} already up-to-date"
            updated = False
            recreated = False

        return {
            "success": True if updated or matches else False,
            "updated": updated,
            "recreated": recreated,
            "message": message,
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "recreated": False,
            "message": f"BMH operation error: {str(e)[:50]}...",
        }


def networkdata_present(
    namespace,
    bmh_name,
    defaults,
    pillar_data,
    network_template_path="salt://formulas/bmo/files/network-data.j2",
):
    """
    Ensure that the network data Secret in Kubernetes matches the desired state
    defined by pillar data and Jinja2 template.

    Args:
        namespace (str): The namespace of the network data Secret in Kubernetes.
        bmh_name (str): The name of the Bare Metal Host resource (used for Secret naming).
        defaults (dict): Default values for network configuration.
        pillar_data (dict): Pillar data containing the desired network configuration.
        network_template_path (str, optional): Salt URI to the Jinja2 template file for network data.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.networkdata_present baremetal-operator-system compute-133-26 defaults pillar_data
    """
    try:
        updated = False
        exists = False
        matches = False
        current_network = {}
        desired_network = {}
        differences = {}

        _load_k8s_config()

        core_v1_api = client.CoreV1Api()
        network_data_name = f"{bmh_name}-network-data"

        if "network" in pillar_data:
            try:
                network_secret = core_v1_api.read_namespaced_secret(
                    name=network_data_name, namespace=namespace
                )
                exists = True
                current_network = _decode_k8s_secret(network_secret)
            except ApiException:
                exists = False
                current_network = {}
            except Exception:
                exists = False
                current_network = {}
        else:
            exists = False
            current_network = {}
            message = f"Network data not applicable for {bmh_name}"
            return {"success": True, "updated": False, "message": message}

        if "network" in pillar_data:
            try:
                network_context = {
                    "interface": defaults["interface"],
                    "mac": defaults["mac"],
                    "ip": defaults["ip"],
                    "prefix": defaults["prefix"],
                    "gateway": defaults["gateway"],
                    "nameserver": defaults["nameserver"],
                }
                rendered_network = _render_salt_template(
                    network_template_path, network_context, renderer="jinja"
                )

                import json

                desired_network_json = json.loads(rendered_network)
                desired_network = {"networkData": json.dumps(desired_network_json)}

                if exists:
                    current_data = current_network
                    if (
                        isinstance(current_network, dict)
                        and "networkData" in current_network
                    ):
                        try:
                            current_data = json.loads(current_network["networkData"])
                        except Exception:
                            current_data = current_network
                    desired_data = json.loads(desired_network["networkData"])
                    for key in desired_data:
                        if (
                            key not in current_data
                            or current_data[key] != desired_data[key]
                        ):
                            differences[key] = {"desired": desired_data[key]}
                    matches = len(differences) == 0
                else:
                    matches = False
            except Exception as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Network data render failed: {str(e)[:50]}...",
                }
        else:
            desired_network = {}
            matches = False
            message = f"Network data not applicable for {bmh_name}"
            return {"success": True, "updated": False, "message": message}

        if "network" in pillar_data and (not exists or not matches):
            try:
                body = client.V1Secret(
                    metadata=client.V1ObjectMeta(
                        name=network_data_name, namespace=namespace
                    ),
                    string_data=desired_network,
                    type="Opaque",
                )
                if exists:
                    core_v1_api.replace_namespaced_secret(
                        name=network_data_name, namespace=namespace, body=body
                    )
                    updated = True
                    message = f"Network Secret {network_data_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(namespace=namespace, body=body)
                    updated = True
                    message = f"Network Secret {network_data_name} created"
            except ApiException as e:
                updated = False
                message = f"Network Secret {network_data_name} operation failed: {str(e)[:50]}..."
        else:
            message = f"Network data for {bmh_name} up-to-date or not applicable"
            updated = False

        return {
            "success": True if updated or matches else False,
            "updated": updated,
            "message": message,
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Network data operation error: {str(e)[:50]}...",
        }


def userdata_present(
    namespace,
    bmh_name,
    pillar_data,
    userdata_template_path="salt://formulas/bmo/files/cloudinit.j2",
):
    """
    Ensure that the userdata Secret in Kubernetes matches the desired state
    defined by pillar data and Jinja2 template.

    Args:
        namespace (str): The namespace of the userdata Secret in Kubernetes.
        bmh_name (str): The name of the Bare Metal Host resource (used for Secret naming).
        pillar_data (dict): Pillar data containing the desired userdata configuration.
        userdata_template_path (str, optional): Salt URI to the Jinja2 template file for userdata.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.userdata_present baremetal-operator-system compute-133-26 pillar_data
    """
    try:
        updated = False
        exists = False
        matches = False
        current_userdata = {}
        desired_userdata = {}
        differences = {}

        _load_k8s_config()

        core_v1_api = client.CoreV1Api()
        userdata_name = f"{bmh_name}-user-data"

        if "network" in pillar_data:
            try:
                userdata_secret = core_v1_api.read_namespaced_secret(
                    name=userdata_name, namespace=namespace
                )
                exists = True
                current_userdata = _decode_k8s_secret(userdata_secret)
            except ApiException:
                exists = False
                current_userdata = {}
            except Exception:
                exists = False
                current_userdata = {}
        else:
            exists = False
            current_userdata = {}
            message = f"Userdata not applicable for {bmh_name}"
            return {"success": True, "updated": False, "message": message}

        if "network" in pillar_data:
            try:
                full_pillar = __salt__["pillar.get"]("", {})
                userdata_context = {
                    "pillar": {
                        "node_deploy_key": full_pillar.get("node_deploy_key", "")
                    },
                    "pass": pillar_data.get("root_password_crypted", ""),
                }
                rendered_userdata = _render_salt_template(
                    userdata_template_path, userdata_context, renderer="jinja"
                )

                desired_userdata = {"userData": rendered_userdata}

                if exists:
                    current_data = (
                        current_userdata.get("userData", "")
                        if isinstance(current_userdata, dict)
                        and "userData" in current_userdata
                        else (
                            list(current_userdata.values())[0]
                            if isinstance(current_userdata, dict)
                            and len(current_userdata) == 1
                            else ""
                        )
                    )
                    desired_data = desired_userdata.get("userData", "")
                    if current_data != desired_data:
                        differences["userData"] = {
                            "desired": desired_data[:50] + "..."
                            if len(desired_data) > 50
                            else desired_data
                        }
                    matches = len(differences) == 0
                else:
                    matches = False
            except Exception as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Userdata render failed: {str(e)[:50]}...",
                }
        else:
            desired_userdata = {}
            matches = False
            message = f"Userdata not applicable for {bmh_name}"
            return {"success": True, "updated": False, "message": message}

        if "network" in pillar_data and (not exists or not matches):
            try:
                body = client.V1Secret(
                    metadata=client.V1ObjectMeta(
                        name=userdata_name, namespace=namespace
                    ),
                    string_data=desired_userdata,
                    type="Opaque",
                )
                if exists:
                    core_v1_api.replace_namespaced_secret(
                        name=userdata_name, namespace=namespace, body=body
                    )
                    updated = True
                    message = f"Userdata Secret {userdata_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(namespace=namespace, body=body)
                    updated = True
                    message = f"Userdata Secret {userdata_name} created"
            except ApiException as e:
                updated = False
                message = f"Userdata Secret {userdata_name} operation failed: {str(e)[:50]}..."
        else:
            message = f"Userdata for {bmh_name} up-to-date or not applicable"
            updated = False

        return {
            "success": True if updated or matches else False,
            "updated": updated,
            "message": message,
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Userdata operation error: {str(e)[:50]}...",
        }


def host_bmc_auth_present(
    namespace,
    bmh_name,
    ipmi,
    pillar_data,
    bmc_auth_template_path="salt://formulas/bmo/files/bmc-auth.j2",
):
    """
    Ensure that a host-specific BMC authentication Secret in Kubernetes matches the desired state
    defined by pillar data and Jinja2 template.

    Args:
        namespace (str): The namespace of the Secret in Kubernetes.
        bmh_name (str): The name of the Bare Metal Host resource (used for Secret naming).
        ipmi (str): Default IPMI password if not in pillar.
        pillar_data (dict): Pillar data containing the desired BMC authentication configuration.
        bmc_auth_template_path (str, optional): Salt URI to the Jinja2 template file for BMC auth Secret.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.host_bmc_auth_present baremetal-operator-system compute-133-26 ipmi pillar_data
    """
    try:
        updated = False
        exists = False
        matches = False
        current_secret = {}
        desired_secret = {}
        differences = {}
        secret_name = f"{bmh_name}-bmc-auth"

        _load_k8s_config()

        core_v1_api = client.CoreV1Api()

        try:
            secret = core_v1_api.read_namespaced_secret(
                name=secret_name, namespace=namespace
            )
            exists = True
            current_secret = _decode_k8s_secret(secret)
        except ApiException:
            exists = False
            current_secret = {}
        except Exception:
            exists = False
            current_secret = {}

        try:
            full_pillar = __salt__["pillar.get"]("", {})
            bmc_auth_context = {
                "pillar": {
                    "name": bmh_name,
                    "bmo_namespace": full_pillar.get("bmo_namespace", namespace),
                    "ipmi_password": pillar_data.get("bmc", {}).get(
                        "password", full_pillar.get("ipmi-password", ipmi)
                    ),
                }
            }
            rendered_bmc_auth = _render_salt_template(
                bmc_auth_template_path, bmc_auth_context
            )

            import yaml

            desired_secret_full = (
                rendered_bmc_auth
                if isinstance(rendered_bmc_auth, dict)
                else yaml.safe_load(rendered_bmc_auth)
            )
            if "metadata" in desired_secret_full:
                desired_secret_full["metadata"]["name"] = secret_name
            desired_secret = desired_secret_full.get("stringData", {})

            if exists:
                for key in desired_secret:
                    if (
                        key not in current_secret
                        or current_secret[key] != desired_secret[key]
                    ):
                        differences[key] = {
                            "desired": desired_secret[key][:10] + "..."
                            if len(desired_secret[key]) > 10
                            else desired_secret[key]
                        }
                matches = len(differences) == 0
            else:
                matches = False
        except Exception as e:
            return {
                "success": False,
                "updated": False,
                "message": f"BMC auth render failed: {str(e)[:50]}...",
            }

        if not exists or not matches:
            try:
                body = client.V1Secret(
                    metadata=client.V1ObjectMeta(name=secret_name, namespace=namespace),
                    string_data=desired_secret,
                    type=desired_secret_full.get("type", "Opaque"),
                )
                if exists:
                    core_v1_api.replace_namespaced_secret(
                        name=secret_name, namespace=namespace, body=body
                    )
                    updated = True
                    message = f"BMC Secret {secret_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(namespace=namespace, body=body)
                    updated = True
                    message = f"BMC Secret {secret_name} created"
            except ApiException as e:
                updated = False
                message = f"BMC Secret {secret_name} operation failed: {str(e)[:50]}..."
        else:
            message = f"BMC Secret {secret_name} up-to-date"
            updated = False

        return {
            "success": True if updated or matches else False,
            "updated": updated,
            "message": message,
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"BMC auth operation error: {str(e)[:50]}...",
        }


def uuids_secret_present(
    namespace,
    secret_name,
    pillar_data,
    deployment_name="salt-master",
    wait_timeout=300,
    wait_interval=10,
    salt_check_timeout=120,
    salt_check_interval=5,
    salt_check_key="salt-master:uuids",
):
    """
    Ensure that a Kubernetes Secret containing UUIDs from pillar data matches the desired state.
    Extracts UUIDs by looping through the 'bmh' dictionary in pillar data, collecting 'uuid' from each host.
    If updated, restarts the specified deployment, waits for it to become ready, and verifies salt-master responsiveness by fetching pillar data.

    Args:
        namespace (str): The namespace of the Secret and Deployment in Kubernetes.
        secret_name (str): The name of the Secret to create or update.
        pillar_data (dict): Pillar data containing the BMH hosts under 'bmh' with 'uuid' fields.
        deployment_name (str, optional): The name of the deployment to restart if updated. Defaults to 'salt-master'.
        wait_timeout (int, optional): Maximum time in seconds to wait for deployment readiness. Defaults to 300 (5 minutes).
        wait_interval (int, optional): Interval in seconds between checks for deployment readiness. Defaults to 10 seconds.
        salt_check_timeout (int, optional): Maximum time in seconds to wait for salt-master responsiveness. Defaults to 120 seconds.
        salt_check_interval (int, optional): Interval in seconds between salt-master responsiveness checks. Defaults to 5 seconds.
        salt_check_key (str, optional): The pillar key to fetch for checking salt-master responsiveness. Defaults to 'salt-master:uuids'.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'restarted' (bool), 'waited' (bool), 'salt_responded' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.uuids_secret_present baremetal-operator-system salt-master-uuids pillar_data
    """
    try:
        updated = False
        restarted = False
        waited = False
        salt_responded = False
        exists = False
        matches = False
        current_secret = {}
        desired_secret = {}
        differences = {}

        # Step 1: Extract UUIDs by looping through 'bmh' dictionary in pillar data
        uuids_list = []
        debug_msg = "Pillar data structure: "
        if isinstance(pillar_data, dict):
            debug_msg += "dict; "
            # Try to access 'bmh' directly in pillar_data or under 'bmh' key
            bmh_data = pillar_data.get("bmh", {})
            if not bmh_data or not isinstance(bmh_data, dict):
                debug_msg += "bmh not found or not dict; "
                # If 'bmh' is not found, check if pillar_data itself contains host entries (unlikely but for completeness)
                bmh_data = (
                    pillar_data
                    if any(
                        isinstance(v, dict) and "uuid" in v
                        for v in pillar_data.values()
                    )
                    else {}
                )
                debug_msg += f"bmh as pillar_data: {bool(bmh_data)}; "
            else:
                debug_msg += "bmh found; "

            if bmh_data and isinstance(bmh_data, dict):
                # Loop through each host entry in bmh_data to extract 'uuid'
                for host_name, host_data in bmh_data.items():
                    if isinstance(host_data, dict) and "uuid" in host_data:
                        uuid_val = host_data.get("uuid", "")
                        if uuid_val and isinstance(uuid_val, str):
                            uuids_list.append(uuid_val)
                debug_msg += f"extracted {len(uuids_list)} UUIDs from bmh hosts; "
                debug_msg += f"bmh host keys: {list(bmh_data.keys())[:5]}; "
            else:
                debug_msg += "no valid bmh data to extract UUIDs; "
        else:
            debug_msg += "not dict; "

        # Join the UUIDs into a single string with newlines
        uuids_str = "\n".join(uuids_list) if uuids_list else ""
        debug_msg += f"uuids_str preview: {repr(uuids_str)[:50]}...; "

        # Check if UUIDs string is empty or whitespace-only
        if not uuids_str or uuids_str.strip() == "":
            return {
                "success": True,
                "updated": False,
                "restarted": False,
                "waited": False,
                "salt_responded": False,
                "message": f"No UUIDs extracted for Secret {secret_name}; no action taken. {debug_msg}",
            }

        _load_k8s_config()

        core_v1_api = client.CoreV1Api()
        apps_v1_api = client.AppsV1Api()

        try:
            secret = core_v1_api.read_namespaced_secret(
                name=secret_name, namespace=namespace
            )
            exists = True
            current_secret = _decode_k8s_secret(secret)
        except ApiException:
            exists = False
            current_secret = {}
        except Exception:
            exists = False
            current_secret = {}

        desired_secret = {"uuid": uuids_str}

        if exists:
            for key in desired_secret:
                if (
                    key not in current_secret
                    or current_secret[key] != desired_secret[key]
                ):
                    differences[key] = {
                        "desired": desired_secret[key][:50] + "..."
                        if len(desired_secret[key]) > 50
                        else desired_secret[key]
                    }
            matches = len(differences) == 0
        else:
            matches = False

        if not exists or not matches:
            try:
                body = client.V1Secret(
                    metadata=client.V1ObjectMeta(name=secret_name, namespace=namespace),
                    string_data=desired_secret,
                    type="Opaque",
                )
                if exists:
                    core_v1_api.replace_namespaced_secret(
                        name=secret_name, namespace=namespace, body=body
                    )
                    updated = True
                    message = f"UUID Secret {secret_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(namespace=namespace, body=body)
                    updated = True
                    message = f"UUID Secret {secret_name} created"
            except ApiException as e:
                updated = False
                message = (
                    f"UUID Secret {secret_name} operation failed: {str(e)[:50]}..."
                )
        else:
            message = f"UUID Secret {secret_name} up-to-date"
            updated = False

        if updated:
            try:
                deployment = apps_v1_api.read_namespaced_deployment(
                    name=deployment_name, namespace=namespace
                )
                selector = deployment.spec.selector.match_labels
                pods = core_v1_api.list_namespaced_pod(
                    namespace=namespace,
                    label_selector=",".join([f"{k}={v}" for k, v in selector.items()]),
                )
                for pod in pods.items:
                    core_v1_api.delete_namespaced_pod(
                        name=pod.metadata.name,
                        namespace=namespace,
                        body=client.V1DeleteOptions(),
                    )
                restarted = True
                message += f"; {deployment_name} restarted"

                # Step 2: Wait for the deployment to become ready
                import time

                wait_time = 0
                while wait_time < wait_timeout:
                    try:
                        status = apps_v1_api.read_namespaced_deployment_status(
                            name=deployment_name, namespace=namespace
                        )
                        ready_replicas = status.status.ready_replicas or 0
                        desired_replicas = status.spec.replicas
                        if ready_replicas == desired_replicas:
                            waited = True
                            message += f"; {deployment_name} ready ({wait_time}s)"
                            break
                    except ApiException:
                        message += f"; {deployment_name} status check failed"
                        break
                    time.sleep(wait_interval)
                    wait_time += wait_interval
                if wait_time >= wait_timeout and not waited:
                    message += f"; {deployment_name} timeout ({wait_timeout}s)"

                # Step 3: If deployment is ready, wait a mandatory 20 seconds before checking salt-master responsiveness
                if waited:
                    message += "; Pausing for 20 seconds before salt-master responsiveness check"
                    time.sleep(20)

                    # Step 4: Verify salt-master responsiveness by fetching pillar data
                    salt_check_time = 0
                    while salt_check_time < salt_check_timeout:
                        try:
                            # Attempt to fetch the specified pillar key to verify salt-master responsiveness
                            pillar_result = __salt__["pillar.get"](
                                salt_check_key, default=None
                            )
                            if pillar_result is not None:
                                salt_responded = True
                                message += f"; salt-master responded with pillar data for '{salt_check_key}' ({salt_check_time + 20}s total)"
                                break
                            else:
                                message += f"; salt-master returned None for pillar key '{salt_check_key}' ({salt_check_time + 20}s total), retrying..."
                        except Exception as pillar_err:
                            message += f"; salt-master pillar fetch error for '{salt_check_key}' ({salt_check_time + 20}s total): {str(pillar_err)[:50]}..., retrying..."
                        time.sleep(salt_check_interval)
                        salt_check_time += salt_check_interval
                    if salt_check_time >= salt_check_timeout and not salt_responded:
                        message += f"; salt-master responsiveness timeout for pillar fetch ({salt_check_timeout + 20}s total)"
            except ApiException as e:
                restarted = False
                message += f"; {deployment_name} restart failed: {str(e)[:50]}..."
            except Exception as e:
                restarted = False
                message += f"; {deployment_name} restart error: {str(e)[:50]}..."

        return {
            "success": True
            if (updated and restarted and waited and salt_responded)
            or (matches and not updated)
            else False,
            "updated": updated,
            "restarted": restarted,
            "waited": waited,
            "salt_responded": salt_responded,
            "message": message,
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "restarted": False,
            "waited": False,
            "salt_responded": False,
            "message": f"UUID Secret operation error: {str(e)[:50]}...",
        }


def mariadb_instance_present(
    namespace,
    instance_name,
    root_password,
    secret_name,
    image="mariadb:10.6",
    pvc_name="mariadb-pvc",
    storage_size="1Gi",
    storage_class="local-storage",
    replicas=1,
    limits_cpu="500m",
    limits_memory="512Mi",
    requests_cpu="200m",
    requests_memory="256Mi",
    admin_host_access="%",
):
    """
    Ensure that a MariaDB instance is present in Kubernetes using the MariaDB Operator.
    Creates a Secret for the root password if it doesn't exist, then creates or updates the MariaDB Custom Resource.
    Additionally, ensures the root user has access from the specified host or IP pattern.

    Args:
        namespace (str): The namespace of the MariaDB instance and Secret in Kubernetes.
        instance_name (str): The name of the MariaDB instance (Custom Resource).
        root_password (str): The root password for MariaDB (stored in a Secret).
        secret_name (str): The name of the Secret to store the root password.
        image (str, optional): The MariaDB Docker image to use. Defaults to 'mariadb:10.6'.
        pvc_name (str, optional): Ignored since operator creates PVC. Kept for compatibility. Defaults to 'mariadb-pvc'.
        storage_size (str, optional): Storage size for the PVC. Defaults to '1Gi'.
        storage_class (str, optional): Storage class for the PVC. Defaults to 'local-storage'.
        replicas (int, optional): Number of replicas for the MariaDB instance. Defaults to 1.
        limits_cpu (str, optional): CPU limit for the MariaDB container. Defaults to '500m'.
        limits_memory (str, optional): Memory limit for the MariaDB container. Defaults to '512Mi'.
        requests_cpu (str, optional): CPU request for the MariaDB container. Defaults to '200m'.
        requests_memory (str, optional): Memory request for the MariaDB container. Defaults to '256Mi'.
        admin_host_access (str, optional): Host or IP pattern to grant root access from. Defaults to '%'.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'secret_updated' (bool), 'pvc_available' (bool), 'root_access_updated' (bool), and 'message' (str).
    """
    try:
        updated = False
        secret_updated = False
        root_access_updated = False
        secret_exists = False
        mariadb_exists = False
        matches = False
        pvc_available = False

        message = f"Configuring MariaDB with storage class: {storage_class}"

        _load_k8s_config()

        core_v1_api = client.CoreV1Api()
        custom_api = client.CustomObjectsApi()

        # Step 1: Check if Secret for root password exists
        try:
            secret = core_v1_api.read_namespaced_secret(
                name=secret_name, namespace=namespace
            )
            secret_exists = True
            current_password = (
                secret.string_data.get("password", "") if secret.string_data else ""
            )
            if not current_password and secret.data:
                import base64

                current_password = base64.b64decode(
                    secret.data.get("password", "")
                ).decode("utf-8")
            if current_password != root_password:
                secret_updated = True
            else:
                secret_updated = False
        except ApiException as e:
            if e.status == 404:
                secret_exists = False
                secret_updated = True
            else:
                return {
                    "success": False,
                    "updated": False,
                    "secret_updated": False,
                    "pvc_available": False,
                    "root_access_updated": False,
                    "message": f"Error fetching Secret {secret_name}: {str(e)[:100]}...; {message}",
                }

        # Step 2: Create or update Secret if necessary
        if not secret_exists or secret_updated:
            try:
                secret_body = client.V1Secret(
                    metadata=client.V1ObjectMeta(name=secret_name, namespace=namespace),
                    string_data={"password": root_password},
                    type="Opaque",
                )
                if secret_exists:
                    core_v1_api.replace_namespaced_secret(
                        name=secret_name, namespace=namespace, body=secret_body
                    )
                    message += f"; Secret {secret_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(
                        namespace=namespace, body=secret_body
                    )
                    message += f"; Secret {secret_name} created"
                secret_updated = True
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "secret_updated": False,
                    "pvc_available": False,
                    "root_access_updated": False,
                    "message": f"Failed to create/update Secret {secret_name}: {str(e)[:100]}...; {message}",
                }
        else:
            message += f"; Secret {secret_name} already up-to-date"

        # Step 3: Check if MariaDB instance exists
        try:
            group = "k8s.mariadb.com"
            version = "v1alpha1"
            plural = "mariadbs"
            mariadb = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=instance_name,
            )
            mariadb_exists = True
            # Check if key fields match desired state for potential update
            current_spec = mariadb.get("spec", {})
            desired_image = image
            desired_replicas = replicas
            current_image = current_spec.get("image", "")
            current_replicas = current_spec.get("replicas", 1)
            current_storage = current_spec.get("storage", {})
            current_storage_class = current_storage.get("storageClassName", "")
            current_storage_size = current_storage.get("size", "")
            if (
                current_image != desired_image
                or current_replicas != desired_replicas
                or current_storage_size != storage_size
                or current_storage_class != storage_class
            ):
                matches = False
            else:
                matches = True
        except ApiException as e:
            if e.status == 404:
                mariadb_exists = False
                matches = False
            else:
                return {
                    "success": False,
                    "updated": False,
                    "secret_updated": secret_updated,
                    "pvc_available": False,
                    "root_access_updated": False,
                    "message": f"Error fetching MariaDB instance {instance_name}: {str(e)[:100]}...; {message}",
                }

        # Step 4: No PVC check since operator will create it
        pvc_available = False
        message += f"; Skipping PVC check, operator will create PVC with storage class {storage_class}"

        # Step 5: Create or update MariaDB instance if necessary
        if not mariadb_exists or not matches:
            try:
                group = "k8s.mariadb.com"
                version = "v1alpha1"
                plural = "mariadbs"
                mariadb_body = {
                    "apiVersion": f"{group}/{version}",
                    "kind": "MariaDb",
                    "metadata": {"name": instance_name, "namespace": namespace},
                    "spec": {
                        "image": image,
                        "username": "root",
                        "passwordSecretKeyRef": {
                            "name": secret_name,
                            "key": "password",
                        },
                        "replicas": replicas,
                        "resources": {
                            "limits": {"cpu": limits_cpu, "memory": limits_memory},
                            "requests": {
                                "cpu": requests_cpu,
                                "memory": requests_memory,
                            },
                        },
                        "storage": {
                            "size": storage_size,
                            "storageClassName": storage_class,
                            "accessModes": ["ReadWriteOnce"],
                        },
                    },
                }
                if mariadb_exists:
                    custom_api.replace_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        name=instance_name,
                        body=mariadb_body,
                    )
                    updated = True
                    message += f"; MariaDB instance {instance_name} updated"
                else:
                    custom_api.create_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        body=mariadb_body,
                    )
                    updated = True
                    message += f"; MariaDB instance {instance_name} created"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "secret_updated": secret_updated,
                    "pvc_available": pvc_available,
                    "root_access_updated": False,
                    "message": f"Failed to create/update MariaDB instance {instance_name}: {str(e)[:100]}...; {message}",
                }
        else:
            message += f"; MariaDB instance {instance_name} already up-to-date"
            updated = False

        # Step 6: Ensure root user has access from the specified host/IP pattern
        try:
            # Get the MariaDB pod name
            pod_list = core_v1_api.list_namespaced_pod(
                namespace=namespace,
                label_selector=f"app.kubernetes.io/name={instance_name}",
            )
            if pod_list.items:
                pod_name = pod_list.items[0].metadata.name
                # Construct the kubectl exec command to grant root access
                grant_cmd = f"mysql -u root -p{root_password} -e \"GRANT ALL PRIVILEGES ON *.* TO 'root'@'{admin_host_access}' IDENTIFIED BY '{root_password}' WITH GRANT OPTION; FLUSH PRIVILEGES;\""
                kubectl_cmd = (
                    f"kubectl exec -i {pod_name} -n {namespace} -- {grant_cmd}"
                )
                # Execute the command using Salt's cmd.run
                grant_result = __salt__["cmd.run"](
                    kubectl_cmd, shell=True, ignore_retcode=True
                )
                if "ERROR" not in grant_result:
                    root_access_updated = True
                    message += (
                        f"; Root user access granted for host {admin_host_access}"
                    )
                else:
                    root_access_updated = False
                    message += f"; Failed to grant root access for host {admin_host_access}: {grant_result[:100]}..."
            else:
                root_access_updated = False
                message += (
                    f"; No MariaDB pod found for {instance_name} to grant root access"
                )
        except Exception as e:
            root_access_updated = False
            message += f"; Error granting root access for host {admin_host_access}: {str(e)[:100]}..."

        return {
            "success": True if (updated or matches) else False,
            "updated": updated,
            "secret_updated": secret_updated,
            "pvc_available": pvc_available,
            "root_access_updated": root_access_updated,
            "message": message,
        }
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "secret_updated": False,
            "pvc_available": False,
            "root_access_updated": False,
            "message": f"MariaDB instance operation error: {str(e)[:100]}...",
        }


def local_storage_pv_pvc_present(
    namespace,
    pv_name,
    pvc_name,
    storage_size="1Gi",
    node_name=None,
    path="/mnt/local-storage",
    storage_class="local-storage",
):
    """
    Ensure that a Persistent Volume (PV) is present in Kubernetes using a specified storage class for local storage.
    The PV is tied to a local path. Checks if the local path exists on the node before proceeding.
    Does not manage PVC creation since the operator will handle it. Sanitizes PV name to meet Kubernetes naming conventions.

    Args:
        namespace (str): The namespace of the PVC (unused since PVC is not created, kept for compatibility).
        pv_name (str): The name of the Persistent Volume (will be sanitized).
        pvc_name (str): Ignored since PVC is not created. Kept for compatibility.
        storage_size (str, optional): Storage size for the PV. Defaults to '1Gi'.
        node_name (str, optional): The name of the node to bind the local storage PV to. Not used in this simplified version to avoid validation issues.
        path (str, optional): The host path on the node for local storage. Defaults to '/mnt/local-storage'.
        storage_class (str, optional): The storage class to use for the PV. Defaults to 'local-storage'.

    Returns:
        dict: A dictionary with 'success' (bool), 'pv_updated' (bool), 'pvc_updated' (bool), 'bound' (bool), and 'message' (str).
    """
    try:
        pv_updated = False
        pvc_updated = False
        bound = False

        # Sanitize pv_name to meet Kubernetes naming conventions
        def sanitize_name(name):
            import re

            # Convert to lowercase
            sanitized = name.lower()
            # Replace invalid characters with hyphens
            sanitized = re.sub(r"[^a-z0-9.-]", "-", sanitized)
            # Remove leading/trailing hyphens or periods
            sanitized = sanitized.strip("-").strip(".")
            # Truncate to 253 characters (Kubernetes max for most resource names)
            sanitized = sanitized[:253]
            # If empty after sanitization, provide a fallback
            if not sanitized:
                sanitized = "sanitized-name"
            return sanitized

        original_pv_name = pv_name
        pv_name = sanitize_name(pv_name)
        message = f"Sanitized PV name: {original_pv_name} -> {pv_name}; PVC management skipped, operator will handle PVC creation"

        # Step 1: Ensure the local path exists on the node
        if not __salt__["file.directory_exists"](path):
            try:
                __salt__["file.mkdir"](path)
                message += f"; Created directory {path} on node"
            except Exception as e:
                return {
                    "success": False,
                    "pv_updated": False,
                    "pvc_updated": False,
                    "bound": False,
                    "message": f"Failed to create directory {path} on node: {str(e)[:100]}...; {message}",
                }
        else:
            message += f"; Directory {path} already exists on node"

        _load_k8s_config()

        core_v1_api = client.CoreV1Api()

        # Step 2: Check if PV exists
        try:
            existing_pv = core_v1_api.read_persistent_volume(name=pv_name)
            pv_exists = True
        except ApiException as e:
            if e.status == 404:
                pv_exists = False
            else:
                return {
                    "success": False,
                    "pv_updated": False,
                    "pvc_updated": False,
                    "bound": False,
                    "message": f"Error fetching PV {pv_name}: {str(e)[:100]}...; {message}",
                }

        # Step 3: Create or update PV if it doesn't exist or needs updating
        if not pv_exists:
            try:
                pv_body = client.V1PersistentVolume(
                    metadata=client.V1ObjectMeta(name=pv_name),
                    spec=client.V1PersistentVolumeSpec(
                        capacity={"storage": storage_size},
                        access_modes=["ReadWriteOnce"],
                        storage_class_name=storage_class,
                        host_path=client.V1HostPathVolumeSource(path=path),
                    ),
                )
                core_v1_api.create_persistent_volume(body=pv_body)
                pv_updated = True
                message += f"; PV {pv_name} created with size {storage_size} at {path}"
            except ApiException as e:
                return {
                    "success": False,
                    "pv_updated": False,
                    "pvc_updated": False,
                    "bound": False,
                    "message": f"Failed to create/update PV {pv_name}: {str(e)[:100]}...; {message}",
                }
        else:
            message += f"; PV {pv_name} already exists"
            pv_updated = False

        # Step 4: Skip PVC creation and binding check since operator handles PVC
        message += f"; PVC creation and binding skipped, relying on operator to create PVC with storage class {storage_class}"

        return {
            "success": True if pv_updated or pv_exists else False,
            "pv_updated": pv_updated,
            "pvc_updated": False,
            "bound": False,
            "message": message,
        }

    except Exception as e:
        return {
            "success": False,
            "pv_updated": False,
            "pvc_updated": False,
            "bound": False,
            "message": f"Local storage PV operation error: {str(e)[:100]}...",
        }


def ironic_db_user_setup(
    namespace,
    mariadb_name,
    mariadb_namespace,
    user_name,
    user_password,
    secret_name,
    database_name="ironic-database",
    host="%",
    max_user_connections=100,
    privileges=["ALL PRIVILEGES"],
    table="*",
):
    """
    Ensure that the necessary Kubernetes resources for an Ironic database user are present.
    This includes a Secret for user credentials, a User custom resource, a Database custom resource, and a Grant custom resource.

    Args:
        namespace (str): The namespace for the Secret, User, Database, and Grant resources (typically Ironic namespace).
        mariadb_name (str): The name of the MariaDB instance (Custom Resource) to reference.
        mariadb_namespace (str): The namespace of the MariaDB instance.
        user_name (str): The username for the database user (must match Secret data and User metadata name).
        user_password (str): The password for the database user.
        secret_name (str): The name of the Secret to store the user credentials.
        database_name (str, optional): The name of the database to grant privileges on. Defaults to 'ironic-database'.
        host (str, optional): The host pattern for user access. Defaults to '%'.
        max_user_connections (int, optional): Maximum connections for the user. Defaults to 100.
        privileges (list, optional): List of privileges to grant. Defaults to ['ALL PRIVILEGES'].
        table (str, optional): Table pattern for privileges. Defaults to '*'.

    Returns:
        dict: A dictionary with 'success' (bool), 'secret_updated' (bool), 'user_updated' (bool), 'database_updated' (bool), 'grant_updated' (bool), and 'message' (str).
    """
    try:
        secret_updated = False
        user_updated = False
        database_updated = False
        grant_updated = False
        secret_exists = False
        user_exists = False
        database_exists = False
        grant_exists = False
        secret_matches = False
        user_matches = False
        database_matches = False
        grant_matches = False

        message = f"Setting up Ironic DB user {user_name} for database {database_name} in namespace {namespace}"

        _load_k8s_config()

        core_v1_api = client.CoreV1Api()
        custom_api = client.CustomObjectsApi()

        # Step 1: Check if Secret for user credentials exists
        try:
            secret = core_v1_api.read_namespaced_secret(
                name=secret_name, namespace=namespace
            )
            secret_exists = True
            current_username = (
                secret.string_data.get("username", "") if secret.string_data else ""
            )
            current_password = (
                secret.string_data.get("password", "") if secret.string_data else ""
            )
            if not current_username and secret.data:
                import base64

                current_username = base64.b64decode(
                    secret.data.get("username", "")
                ).decode("utf-8")
                current_password = base64.b64decode(
                    secret.data.get("password", "")
                ).decode("utf-8")
            if current_username != user_name or current_password != user_password:
                secret_updated = True
            else:
                secret_matches = True
                secret_updated = False
        except ApiException as e:
            if e.status == 404:
                secret_exists = False
                secret_updated = True
            else:
                return {
                    "success": False,
                    "secret_updated": False,
                    "user_updated": False,
                    "database_updated": False,
                    "grant_updated": False,
                    "message": f"Error fetching Secret {secret_name}: {str(e)[:100]}...; {message}",
                }

        # Step 2: Create or update Secret if necessary
        if not secret_exists or secret_updated:
            try:
                secret_body = client.V1Secret(
                    metadata=client.V1ObjectMeta(name=secret_name, namespace=namespace),
                    string_data={"username": user_name, "password": user_password},
                    type="Opaque",
                )
                if secret_exists:
                    core_v1_api.replace_namespaced_secret(
                        name=secret_name, namespace=namespace, body=secret_body
                    )
                    secret_updated = True
                    message += f"; Secret {secret_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(
                        namespace=namespace, body=secret_body
                    )
                    secret_updated = True
                    message += f"; Secret {secret_name} created"
            except ApiException as e:
                return {
                    "success": False,
                    "secret_updated": False,
                    "user_updated": False,
                    "database_updated": False,
                    "grant_updated": False,
                    "message": f"Failed to create/update Secret {secret_name}: {str(e)[:100]}...; {message}",
                }
        else:
            message += f"; Secret {secret_name} credentials match, no update needed"

        # Step 3: Check if User custom resource exists
        try:
            group = "k8s.mariadb.com"
            version = "v1alpha1"
            plural = "users"
            user = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=user_name,
            )
            user_exists = True
            current_user_spec = user.get("spec", {})
            current_mariadb_ref = current_user_spec.get("mariaDbRef", {})
            if (
                current_mariadb_ref.get("name", "") != mariadb_name
                or current_mariadb_ref.get("namespace", "") != mariadb_namespace
                or current_user_spec.get("host", "") != host
                or current_user_spec.get("maxUserConnections", 0)
                != max_user_connections
            ):
                user_matches = False
            else:
                user_matches = True
        except ApiException as e:
            if e.status == 404:
                user_exists = False
                user_matches = False
            else:
                return {
                    "success": False,
                    "secret_updated": secret_updated,
                    "user_updated": False,
                    "database_updated": False,
                    "grant_updated": False,
                    "message": f"Error fetching User {user_name}: {str(e)[:100]}...; {message}",
                }

        # Step 4: Create or update User if necessary
        if not user_exists or not user_matches:
            try:
                user_body = {
                    "apiVersion": f"{group}/{version}",
                    "kind": "User",
                    "metadata": {"name": user_name, "namespace": namespace},
                    "spec": {
                        "mariaDbRef": {
                            "name": mariadb_name,
                            "namespace": mariadb_namespace,
                            "waitForIt": True,
                        },
                        "cleanupPolicy": "Delete",
                        "host": host,
                        "maxUserConnections": max_user_connections,
                        "passwordSecretKeyRef": {
                            "name": secret_name,
                            "key": "password",
                        },
                    },
                }
                if (
                    user_exists
                    and "metadata" in user
                    and "resourceVersion" in user["metadata"]
                ):
                    user_body["metadata"]["resourceVersion"] = user["metadata"][
                        "resourceVersion"
                    ]
                if user_exists:
                    custom_api.replace_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        name=user_name,
                        body=user_body,
                    )
                    user_updated = True
                    message += f"; User {user_name} updated"
                else:
                    custom_api.create_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        body=user_body,
                    )
                    user_updated = True
                    message += f"; User {user_name} created"
            except ApiException as e:
                error_details = str(e)
                if hasattr(e, "body") and e.body:
                    error_details += f"; Full Response Body: {e.body[:1000] if len(e.body) > 1000 else e.body}"
                elif hasattr(e, "reason"):
                    error_details += f"; Reason: {e.reason}"
                return {
                    "success": False,
                    "secret_updated": secret_updated,
                    "user_updated": False,
                    "database_updated": False,
                    "grant_updated": False,
                    "message": f"Failed to create/update User {user_name}: {error_details}; {message}",
                }
        else:
            message += f"; User {user_name} spec matches, no update needed"

        # Step 5: Check if Database custom resource exists
        try:
            plural = "databases"
            database = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=database_name,
            )
            database_exists = True
            current_database_spec = database.get("spec", {})
            current_mariadb_ref = current_database_spec.get("mariaDbRef", {})
            if (
                current_mariadb_ref.get("name", "") != mariadb_name
                or current_mariadb_ref.get("namespace", "") != mariadb_namespace
            ):
                database_matches = False
            else:
                database_matches = True
        except ApiException as e:
            if e.status == 404:
                database_exists = False
                database_matches = False
            else:
                return {
                    "success": False,
                    "secret_updated": secret_updated,
                    "user_updated": user_updated,
                    "database_updated": False,
                    "grant_updated": False,
                    "message": f"Error fetching Database {database_name}: {str(e)[:100]}...; {message}",
                }

        # Step 6: Create or update Database if necessary
        if not database_exists or not database_matches:
            try:
                database_body = {
                    "apiVersion": f"{group}/{version}",
                    "kind": "Database",
                    "metadata": {"name": database_name, "namespace": namespace},
                    "spec": {
                        "mariaDbRef": {
                            "name": mariadb_name,
                            "namespace": mariadb_namespace,
                            "waitForIt": True,
                        },
                        "cleanupPolicy": "Delete",
                        "characterSet": "utf8",
                        "collate": "utf8_general_ci",
                    },
                }
                if (
                    database_exists
                    and "metadata" in database
                    and "resourceVersion" in database["metadata"]
                ):
                    database_body["metadata"]["resourceVersion"] = database["metadata"][
                        "resourceVersion"
                    ]
                if database_exists:
                    custom_api.replace_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        name=database_name,
                        body=database_body,
                    )
                    database_updated = True
                    message += f"; Database {database_name} updated"
                else:
                    custom_api.create_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        body=database_body,
                    )
                    database_updated = True
                    message += f"; Database {database_name} created"
            except ApiException as e:
                error_details = str(e)
                if hasattr(e, "body") and e.body:
                    error_details += f"; Full Response Body: {e.body[:1000] if len(e.body) > 1000 else e.body}"
                elif hasattr(e, "reason"):
                    error_details += f"; Reason: {e.reason}"
                return {
                    "success": False,
                    "secret_updated": secret_updated,
                    "user_updated": user_updated,
                    "database_updated": False,
                    "grant_updated": False,
                    "message": f"Failed to create/update Database {database_name}: {error_details}; {message}",
                }
        else:
            message += f"; Database {database_name} spec matches, no update needed"

        # Step 7: Check if Grant custom resource exists
        grant_name = f"{user_name}-grant"
        try:
            plural = "grants"
            # Use mariadb_namespace for Grant to ensure it's in the same namespace as MariaDB instance
            grant = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=mariadb_namespace,
                plural=plural,
                name=grant_name,
            )
            grant_exists = True
            current_grant_spec = grant.get("spec", {})
            current_mariadb_ref = current_grant_spec.get("mariaDbRef", {})
            current_privileges = current_grant_spec.get("privileges", [])
            if (
                current_mariadb_ref.get("name", "") != mariadb_name
                or current_mariadb_ref.get("namespace", "") != mariadb_namespace
                or current_grant_spec.get("database", "") != database_name
                or current_grant_spec.get("host", "") != host
                or current_grant_spec.get("username", "") != user_name
                or (
                    current_grant_spec.get("table", "*") != table
                    if "table" in current_grant_spec
                    else True
                )
                or sorted(current_privileges) != sorted(privileges)
            ):
                grant_matches = False
            else:
                grant_matches = True
        except ApiException as e:
            if e.status == 404:
                grant_exists = False
                grant_matches = False
            else:
                return {
                    "success": False,
                    "secret_updated": secret_updated,
                    "user_updated": user_updated,
                    "database_updated": database_updated,
                    "grant_updated": False,
                    "message": f"Error fetching Grant {grant_name}: {str(e)[:100]}...; {message}",
                }

        # Step 8: Create or update Grant if necessary with a minimal spec first
        if not grant_exists or not grant_matches:
            try:
                plural = "grants"
                # Use mariadb_namespace for Grant to ensure it's in the same namespace as MariaDB instance
                grant_body = {
                    "apiVersion": f"{group}/{version}",
                    "kind": "Grant",
                    "metadata": {"name": grant_name, "namespace": mariadb_namespace},
                    "spec": {
                        "mariaDbRef": {
                            "name": mariadb_name,
                            "namespace": mariadb_namespace,
                            "waitForIt": True,
                        },
                        "cleanupPolicy": "Delete",
                        "database": database_name,
                        "host": host,
                        "privileges": privileges,
                        "username": user_name,
                    },
                }
                if (
                    grant_exists
                    and "metadata" in grant
                    and "resourceVersion" in grant["metadata"]
                ):
                    grant_body["metadata"]["resourceVersion"] = grant["metadata"][
                        "resourceVersion"
                    ]
                if grant_exists:
                    custom_api.replace_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=mariadb_namespace,
                        plural=plural,
                        name=grant_name,
                        body=grant_body,
                    )
                    grant_updated = True
                    message += f"; Grant {grant_name} updated"
                else:
                    custom_api.create_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=mariadb_namespace,
                        plural=plural,
                        body=grant_body,
                    )
                    grant_updated = True
                    message += f"; Grant {grant_name} created"
            except ApiException as e:
                error_details = f"Status: {e.status if hasattr(e, 'status') else 'Unknown'}, Reason: {e.reason if hasattr(e, 'reason') else 'Unknown'}"
                if hasattr(e, "body") and e.body:
                    error_details += f"; Full Response Body: {e.body[:1000] if len(e.body) > 1000 else e.body}"
                elif hasattr(e, "headers"):
                    error_details += f"; Headers: {e.headers}"
                message += f"; DEBUG - Attempted Grant spec in namespace {mariadb_namespace}: {grant_body['spec']}"
                return {
                    "success": False,
                    "secret_updated": secret_updated,
                    "user_updated": user_updated,
                    "database_updated": database_updated,
                    "grant_updated": False,
                    "message": f"Failed to create/update Grant {grant_name}: {error_details}; {message}",
                }
        else:
            message += f"; Grant {grant_name} spec matches, no update needed"

        return {
            "success": True
            if (
                secret_updated
                or user_updated
                or database_updated
                or grant_updated
                or (
                    secret_matches
                    and user_matches
                    and database_matches
                    and grant_matches
                )
            )
            else False,
            "secret_updated": secret_updated,
            "user_updated": user_updated,
            "database_updated": database_updated,
            "grant_updated": grant_updated,
            "message": message,
        }
    except Exception as e:
        error_details = f"General Exception: {str(e)}"
        return {
            "success": False,
            "secret_updated": False,
            "user_updated": False,
            "database_updated": False,
            "grant_updated": False,
            "message": f"Ironic DB user setup error: {error_details}; {message}",
        }


def mariadb_database_present(
    namespace,
    database_name,
    mariadb_name,
    mariadb_namespace,
    character_set="utf8",
    collate="utf8_general_ci",
    cleanup_policy="Delete",
):
    """
    Ensure that a Database custom resource is present in Kubernetes using the MariaDB Operator.
    Creates or updates the Database resource to ensure a specific database exists in the MariaDB instance.

    Args:
        namespace (str): The namespace for the Database resource (often the same as the application namespace).
        database_name (str): The name of the Database resource and the actual database in MariaDB.
        mariadb_name (str): The name of the MariaDB instance to reference.
        mariadb_namespace (str): The namespace of the MariaDB instance.
        character_set (str, optional): The character set for the database. Defaults to 'utf8'.
        collate (str, optional): The collation for the database. Defaults to 'utf8_general_ci'.
        cleanup_policy (str, optional): Cleanup policy for the resource. Defaults to 'Delete'.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).
    """
    try:
        updated = False
        exists = False
        matches = False

        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "k8s.mariadb.com"
        version = "v1alpha1"
        plural = "databases"

        message = f"Configuring Database {database_name} in namespace {namespace}"

        # Check if Database resource exists
        try:
            database = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=database_name,
            )
            exists = True
            current_spec = database.get("spec", {})
            desired_spec = {
                "mariaDbRef": {
                    "name": mariadb_name,
                    "namespace": mariadb_namespace,
                    "waitForIt": True,
                },
                "characterSet": character_set,
                "cleanupPolicy": cleanup_policy,
                "collate": collate,
            }
            # Compare current spec with desired spec
            matches = current_spec == desired_spec
        except ApiException as e:
            if e.status == 404:
                exists = False
                matches = False
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error fetching Database {database_name}: {str(e)[:100]}...; {message}",
                }

        # Create or update Database if necessary
        if not exists or not matches:
            try:
                database_body = {
                    "apiVersion": f"{group}/{version}",
                    "kind": "Database",
                    "metadata": {"name": database_name, "namespace": namespace},
                    "spec": {
                        "mariaDbRef": {
                            "name": mariadb_name,
                            "namespace": mariadb_namespace,
                            "waitForIt": True,
                        },
                        "characterSet": character_set,
                        "cleanupPolicy": cleanup_policy,
                        "collate": collate,
                    },
                }
                if exists:
                    # Include resourceVersion for update
                    if (
                        "metadata" in database
                        and "resourceVersion" in database["metadata"]
                    ):
                        database_body["metadata"]["resourceVersion"] = database[
                            "metadata"
                        ]["resourceVersion"]
                    custom_api.replace_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        name=database_name,
                        body=database_body,
                    )
                    updated = True
                    message += f"; Database {database_name} updated"
                else:
                    custom_api.create_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        body=database_body,
                    )
                    updated = True
                    message += f"; Database {database_name} created"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create/update Database {database_name}: Status: {e.status}, Reason: {e.reason}; Full Response Body: {str(e.body)[:500]}...; {message}",
                }
        else:
            message += f"; Database {database_name} already up-to-date"
            updated = False

        return {
            "success": True if (updated or matches) else False,
            "updated": updated,
            "message": message,
        }
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Database operation error for {database_name}: {str(e)[:100]}...",
        }


def generate_tls_secret(
    namespace, secret_name, common_name="ironic-operator", validity_days=365
):
    """
    Generate a TLS key pair (private key and certificate) and store them in a Kubernetes Secret.
    This is useful for securing communications, such as for the Ironic Standalone Operator.

    Args:
        namespace (str): The Kubernetes namespace where the Secret will be created.
        secret_name (str): The name of the Secret to store the TLS key pair.
        common_name (str, optional): The Common Name (CN) for the certificate subject. Defaults to 'ironic-operator'.
        validity_days (int, optional): The number of days the certificate is valid for. Defaults to 365 (1 year).

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).
    """
    try:
        updated = False
        exists = False

        _load_k8s_config()

        core_v1_api = client.CoreV1Api()

        message = (
            f"Generating TLS key pair for Secret {secret_name} in namespace {namespace}"
        )

        # Check if Secret already exists
        try:
            core_v1_api.read_namespaced_secret(name=secret_name, namespace=namespace)
            exists = True
            message += f"; Secret {secret_name} already exists, skipping generation"
            return {"success": True, "updated": False, "message": message}
        except ApiException as e:
            if e.status == 404:
                exists = False
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking Secret {secret_name}: {str(e)[:100]}...; {message}",
                }

        # Generate TLS key pair if Secret does not exist
        try:
            import base64
            import datetime

            from cryptography import x509
            from cryptography.hazmat.backends import default_backend
            from cryptography.hazmat.primitives import hashes, serialization
            from cryptography.hazmat.primitives.asymmetric import rsa
            from cryptography.x509.oid import NameOID

            # Generate private key
            private_key = rsa.generate_private_key(
                public_exponent=65537, key_size=2048, backend=default_backend()
            )
            public_key = private_key.public_key()

            # Create certificate subject and issuer (self-signed)
            subject = issuer = x509.Name(
                [x509.NameAttribute(NameOID.COMMON_NAME, common_name)]
            )

            # Build self-signed certificate
            cert = (
                x509.CertificateBuilder()
                .subject_name(subject)
                .issuer_name(issuer)
                .public_key(public_key)
                .serial_number(x509.random_serial_number())
                .not_valid_before(datetime.datetime.utcnow())
                .not_valid_after(
                    datetime.datetime.utcnow() + datetime.timedelta(days=validity_days)
                )
                .sign(private_key, hashes.SHA256(), default_backend())
            )

            # Encode private key and certificate to PEM format
            private_key_pem = private_key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.TraditionalOpenSSL,
                encryption_algorithm=serialization.NoEncryption(),
            ).decode("utf-8")

            cert_pem = cert.public_bytes(encoding=serialization.Encoding.PEM).decode(
                "utf-8"
            )

            message += f"; TLS key pair generated with CN={common_name}, valid for {validity_days} days"
        except ImportError:
            return {
                "success": False,
                "updated": False,
                "message": f"Error: 'cryptography' library not installed. Install with 'pip install cryptography'; {message}",
            }
        except Exception as e:
            return {
                "success": False,
                "updated": False,
                "message": f"Failed to generate TLS key pair: {str(e)[:100]}...; {message}",
            }

        # Create Secret with TLS key pair
        try:
            secret_body = client.V1Secret(
                metadata=client.V1ObjectMeta(name=secret_name, namespace=namespace),
                data={
                    "tls.key": base64.b64encode(private_key_pem.encode("utf-8")).decode(
                        "utf-8"
                    ),
                    "tls.crt": base64.b64encode(cert_pem.encode("utf-8")).decode(
                        "utf-8"
                    ),
                },
                type="kubernetes.io/tls",
            )
            core_v1_api.create_namespaced_secret(namespace=namespace, body=secret_body)
            updated = True
            message += f"; Secret {secret_name} created with TLS key pair"
        except ApiException as e:
            return {
                "success": False,
                "updated": False,
                "message": f"Failed to create Secret {secret_name}: Status: {e.status}, Reason: {e.reason}; Full Response Body: {str(e.body)[:500]}...; {message}",
            }

        return {"success": True, "updated": updated, "message": message}
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"TLS Secret operation error for {secret_name}: {str(e)[:100]}...",
        }


def check_ironic_operator(
    namespace="ironic-standalone-operator-system",
    deployment_name="ironic-standalone-operator-controller-manager",
    timeout=60,
):
    """
    Check if the Ironic Operator is installed and available in Kubernetes by verifying the deployment status.
    This mimics the behavior of 'kubectl wait --for=condition=Available'.

    Args:
        namespace (str, optional): The namespace of the Ironic Operator deployment. Defaults to 'ironic-standalone-operator-system'.
        deployment_name (str, optional): The name of the Ironic Operator deployment. Defaults to 'ironic-standalone-operator-controller-manager'.
        timeout (int, optional): Maximum time in seconds to wait for the deployment to become available. Defaults to 60.

    Returns:
        dict: A dictionary with 'success' (bool), 'available' (bool), 'waited' (bool), 'transitioned' (bool), and 'message' (str).
    """
    try:
        import time

        _load_k8s_config()

        apps_v1_api = client.AppsV1Api()

        message = f"Checking Ironic Operator deployment {deployment_name} in namespace {namespace}"
        available = False
        initially_available = False
        waited = False
        transitioned = False

        # Check if deployment exists and get initial availability status
        try:
            status = apps_v1_api.read_namespaced_deployment_status(
                name=deployment_name, namespace=namespace
            )
            message += f"; Deployment {deployment_name} found"
            ready_replicas = status.status.ready_replicas or 0
            desired_replicas = status.spec.replicas
            initially_available = ready_replicas == desired_replicas
            if initially_available:
                message += f"; Deployment {deployment_name} is initially available"
        except ApiException as e:
            if e.status == 404:
                message += f"; Deployment {deployment_name} not found"
                return {
                    "success": False,
                    "available": False,
                    "waited": False,
                    "transitioned": False,
                    "message": message,
                }
            else:
                message += (
                    f"; Error fetching deployment {deployment_name}: {str(e)[:100]}..."
                )
                return {
                    "success": False,
                    "available": False,
                    "waited": False,
                    "transitioned": False,
                    "message": message,
                }

        # If initially available, no need to wait
        if initially_available:
            return {
                "success": True,
                "available": True,
                "waited": False,
                "transitioned": False,
                "message": message,
            }

        # Wait for deployment to become available (ready replicas match desired replicas)
        wait_time = 0
        wait_interval = 5  # Check every 5 seconds
        while wait_time < timeout:
            try:
                status = apps_v1_api.read_namespaced_deployment_status(
                    name=deployment_name, namespace=namespace
                )
                ready_replicas = status.status.ready_replicas or 0
                desired_replicas = status.spec.replicas
                if ready_replicas == desired_replicas:
                    available = True
                    waited = True
                    transitioned = not initially_available
                    message += (
                        f"; Deployment {deployment_name} is available ({wait_time}s)"
                    )
                    break
            except ApiException as e:
                message += f"; Error checking deployment status: {str(e)[:100]}..."
                break
            time.sleep(wait_interval)
            wait_time += wait_interval

        if wait_time >= timeout and not available:
            message += f"; Timeout waiting for deployment {deployment_name} to become available ({timeout}s)"
            available = False
            waited = False
            transitioned = False

        return {
            "success": True if available else False,
            "available": available,
            "waited": waited,
            "transitioned": transitioned,
            "message": message,
        }
    except Exception as e:
        return {
            "success": False,
            "available": False,
            "waited": False,
            "transitioned": False,
            "message": f"Error checking Ironic Operator: {str(e)[:100]}...",
        }


def ironic_instance_present(
    namespace,
    instance_name,
    database_secret_name="ironic-user",
    database_host="ironic-mariadb",
    database_port=3306,
    database_user="ironic",
    database_name="ironic",
    http_port=6385,
    networking_interface="",
    networking_ip="",
    networking_dhcp_range_start="",
    networking_dhcp_range_end="",
    networking_dhcp_range_gateway="",
    networking_dhcp_network_cidr="",
    networking_dhcp_serve_dns=False,
    networking_dhcp_dns_address="",
    inspection_dhcp_all_interfaces=False,
    enable_keepalived=False,
    keepalived_vip="",
    keepalived_interface="eth0",
    tls_secret_name="ironic-tls",
    ssh_public_key="",
    api_secret_name="ironic-api-creds",
    api_username="ironic",
    api_password="",
):
    """
    Ensure that an Ironic instance is present in Kubernetes using the Ironic Standalone Operator.
    Creates or updates the Ironic Custom Resource with specified database connection, networking, and optional Keepalived settings, TLS, SSH key for deploy ramdisk, and API credentials.
    """
    try:
        updated = False
        api_secret_updated = False
        exists = False
        matches = False
        message = (
            f"Configuring Ironic instance {instance_name} in namespace {namespace}"
        )

        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        core_v1_api = client.CoreV1Api()
        group = "ironic.metal3.io"
        version = "v1alpha1"
        plural = "ironics"

        # Step 1: Manage API credentials Secret
        api_secret_exists = False
        api_secret_matches = False
        try:
            api_secret = core_v1_api.read_namespaced_secret(
                name=api_secret_name, namespace=namespace
            )
            api_secret_exists = True
            current_username = (
                api_secret.string_data.get("username", "")
                if api_secret.string_data
                else ""
            )
            current_password = (
                api_secret.string_data.get("password", "")
                if api_secret.string_data
                else ""
            )
            if not current_username and api_secret.data:
                import base64

                current_username = base64.b64decode(
                    api_secret.data.get("username", "")
                ).decode("utf-8")
                current_password = base64.b64decode(
                    api_secret.data.get("password", "")
                ).decode("utf-8")
            if current_username != api_username or (
                api_password and current_password != api_password
            ):
                api_secret_updated = True
            else:
                api_secret_matches = True
                api_secret_updated = False
        except ApiException as e:
            if e.status == 404:
                api_secret_exists = False
                api_secret_updated = True
            else:
                message += (
                    f"; Error fetching API Secret {api_secret_name}: {str(e)[:50]}..."
                )
                return {
                    "success": False,
                    "updated": False,
                    "api_secret_updated": False,
                    "message": message,
                }

        if not api_secret_exists or api_secret_updated:
            try:
                secret_body = client.V1Secret(
                    metadata=client.V1ObjectMeta(
                        name=api_secret_name, namespace=namespace
                    ),
                    string_data={"username": api_username, "password": api_password},
                    type="Opaque",
                )
                if api_secret_exists:
                    core_v1_api.replace_namespaced_secret(
                        name=api_secret_name, namespace=namespace, body=secret_body
                    )
                    api_secret_updated = True
                    message += f"; API Secret {api_secret_name} updated"
                else:
                    core_v1_api.create_namespaced_secret(
                        namespace=namespace, body=secret_body
                    )
                    api_secret_updated = True
                    message += f"; API Secret {api_secret_name} created"
            except ApiException as e:
                message += f"; Failed to create/update API Secret {api_secret_name}: {str(e)[:50]}..."
                return {
                    "success": False,
                    "updated": False,
                    "api_secret_updated": False,
                    "message": message,
                }
        else:
            message += f"; API Secret {api_secret_name} already up-to-date"

        # Step 2: Build desired spec for Ironic instance
        desired_spec = {
            "database": {
                "host": database_host,
                "name": database_name,
                "credentialsName": database_secret_name,
            },
            "apiCredentialsName": api_secret_name,
            "networking": {
                "apiPort": int(http_port),
                "imageServerPort": 6180,
                "imageServerTLSPort": 6183,
            },
            "inspection": {
                "dhcp": {"allInterfaces": bool(inspection_dhcp_all_interfaces)}
            },
        }
        if networking_interface:
            desired_spec["networking"]["interface"] = networking_interface
        if networking_ip:
            desired_spec["networking"]["ipAddress"] = networking_ip
        if (
            networking_dhcp_range_start
            and networking_dhcp_range_end
            and networking_dhcp_network_cidr
        ):
            desired_spec["networking"]["dhcp"] = {
                "networkCIDR": networking_dhcp_network_cidr,
                "rangeBegin": networking_dhcp_range_start,
                "rangeEnd": networking_dhcp_range_end,
            }
            if networking_dhcp_range_gateway:
                desired_spec["networking"]["dhcp"]["gatewayAddress"] = (
                    networking_dhcp_range_gateway
                )
            desired_spec["networking"]["dhcp"]["serveDNS"] = bool(
                networking_dhcp_serve_dns
            )
            if networking_dhcp_dns_address and not networking_dhcp_serve_dns:
                desired_spec["networking"]["dhcp"]["dnsAddress"] = (
                    networking_dhcp_dns_address
                )
        if enable_keepalived and keepalived_vip:
            desired_spec["networking"]["ipAddressManager"] = "keepalived"
            desired_spec["keepalived"] = {
                "enabled": True,
                "vip": keepalived_vip,
                "interface": keepalived_interface,
            }
        if tls_secret_name:
            desired_spec["tls"] = {"certificateName": tls_secret_name}
        if ssh_public_key:
            desired_spec["deployRamdisk"] = {"sshKey": ssh_public_key}

        # Step 3: Check if Ironic instance exists and normalize current spec
        try:
            ironic = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=instance_name,
            )
            exists = True
            current_spec = ironic.get("spec", {})
            current_resource_version = ironic.get("metadata", {}).get(
                "resourceVersion", ""
            )

            # Normalize current spec by adding missing fields with defaults matching desired spec
            def normalize_dict(desired, current):
                normalized = {}
                for key in desired:
                    if key in current:
                        if isinstance(desired[key], dict) and isinstance(
                            current[key], dict
                        ):
                            normalized[key] = normalize_dict(desired[key], current[key])
                        else:
                            normalized[key] = current[key]
                            if key in [
                                "apiPort",
                                "imageServerPort",
                                "imageServerTLSPort",
                            ] and isinstance(normalized[key], (int, float, str)):
                                try:
                                    normalized[key] = int(
                                        float(normalized[key])
                                        if isinstance(normalized[key], str)
                                        else normalized[key]
                                    )
                                except (ValueError, TypeError):
                                    pass
                            if key == "allInterfaces" and isinstance(
                                normalized[key], (bool, str)
                            ):
                                normalized[key] = bool(normalized[key])
                            if key == "enabled" and isinstance(
                                normalized[key], (bool, str)
                            ):
                                normalized[key] = bool(normalized[key])
                    else:
                        # Explicitly set defaults for missing fields based on desired spec
                        normalized[key] = desired[key]
                return normalized

            normalized_current_spec = normalize_dict(desired_spec, current_spec)
            # Compare fully normalized specs
            matches = normalized_current_spec == desired_spec
        except ApiException as e:
            if e.status == 404:
                exists = False
                matches = False
                message += f"; Ironic instance {instance_name} not found, will create"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "api_secret_updated": api_secret_updated,
                    "message": f"Error fetching Ironic instance {instance_name}: {str(e)[:100]}...; {message}",
                }

        # Build the full Ironic body for create/update
        ironic_body = {
            "apiVersion": f"{group}/{version}",
            "kind": "Ironic",
            "metadata": {"name": instance_name, "namespace": namespace},
            "spec": {
                "database": {
                    "host": database_host,
                    "port": int(database_port),
                    "name": database_name,
                    "user": database_user,
                    "credentialsName": database_secret_name,
                },
                "apiCredentialsName": api_secret_name,
                "networking": {
                    "apiPort": int(http_port),
                    "imageServerPort": 6180,
                    "imageServerTLSPort": 6183,
                },
                "inspection": {
                    "dhcp": {"allInterfaces": bool(inspection_dhcp_all_interfaces)}
                },
            },
        }
        if networking_interface:
            ironic_body["spec"]["networking"]["interface"] = networking_interface
        if networking_ip:
            ironic_body["spec"]["networking"]["ipAddress"] = networking_ip
        if (
            networking_dhcp_range_start
            and networking_dhcp_range_end
            and networking_dhcp_network_cidr
        ):
            ironic_body["spec"]["networking"]["dhcp"] = {
                "networkCIDR": networking_dhcp_network_cidr,
                "rangeBegin": networking_dhcp_range_start,
                "rangeEnd": networking_dhcp_range_end,
            }
            if networking_dhcp_range_gateway:
                ironic_body["spec"]["networking"]["dhcp"]["gatewayAddress"] = (
                    networking_dhcp_range_gateway
                )
            ironic_body["spec"]["networking"]["dhcp"]["serveDNS"] = bool(
                networking_dhcp_serve_dns
            )
            if networking_dhcp_dns_address and not networking_dhcp_serve_dns:
                ironic_body["spec"]["networking"]["dhcp"]["dnsAddress"] = (
                    networking_dhcp_dns_address
                )
        if enable_keepalived and keepalived_vip:
            ironic_body["spec"]["networking"]["ipAddressManager"] = "keepalived"
            ironic_body["spec"]["keepalived"] = {
                "enabled": True,
                "vip": keepalived_vip,
                "interface": keepalived_interface,
            }
        if tls_secret_name:
            ironic_body["spec"]["tls"] = {"certificateName": tls_secret_name}
        if ssh_public_key:
            ironic_body["spec"]["deployRamdisk"] = {"sshKey": ssh_public_key}

        # Create or update Ironic instance if necessary
        if not exists or not matches:
            try:
                if exists:
                    if "metadata" in ironic and "resourceVersion" in ironic["metadata"]:
                        ironic_body["metadata"]["resourceVersion"] = ironic["metadata"][
                            "resourceVersion"
                        ]
                    custom_api.replace_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        name=instance_name,
                        body=ironic_body,
                    )
                    updated = True
                    message += f"; Ironic instance {instance_name} updated"
                else:
                    custom_api.create_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        body=ironic_body,
                    )
                    updated = True
                    message += f"; Ironic instance {instance_name} created"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "api_secret_updated": api_secret_updated,
                    "message": f"Failed to create/update Ironic instance {instance_name}: Status: {e.status if hasattr(e, 'status') else 'Unknown'}, Reason: {e.reason if hasattr(e, 'reason') else 'Unknown'}; {message}",
                }
        else:
            message += f"; Ironic instance {instance_name} already up-to-date"
            updated = False

        return {
            "success": True if updated or matches else False,
            "updated": updated,
            "api_secret_updated": api_secret_updated,
            "message": message,
        }
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "api_secret_updated": False,
            "message": f"Ironic instance operation error for {instance_name}: {str(e)[:100]}...",
        }


def image_server_present(
    namespace,
    deployment_name="ironic-image-server",
    service_name="ironic-image-server",
    image="python:3.9-slim",
    port=6180,
    tls_port=6183,
    storage_path="/images",
    pvc_name="ironic-images-pvc",
    storage_size="10Gi",
    storage_class="local-storage",
    service_type="ClusterIP",
    external_ip=None,
):
    """
    Ensure that an image server for Ironic is present in Kubernetes.
    Creates or updates a Deployment and Service to serve images over HTTP for bare metal provisioning.
    Also ensures a PersistentVolumeClaim (PVC) for storing images. Optionally configures the Service for external access.

    Args:
        namespace (str): The namespace for the Deployment, Service, and PVC in Kubernetes.
        deployment_name (str, optional): The name of the Deployment for the image server. Defaults to 'ironic-image-server'.
        service_name (str, optional): The name of the Service for the image server. Defaults to 'ironic-image-server'.
        image (str, optional): The Docker image to use for the image server. Defaults to 'python:3.9-slim'.
        port (int, optional): The HTTP port for serving images. Defaults to 6180.
        tls_port (int, optional): The HTTPS port for serving images (if TLS is configured). Defaults to 6183.
        storage_path (str, optional): The path inside the container to mount the image storage. Defaults to '/images'.
        pvc_name (str, optional): The name of the PersistentVolumeClaim for image storage. Defaults to 'ironic-images-pvc'.
        storage_size (str, optional): The storage size for the PVC. Defaults to '10Gi'.
        storage_class (str, optional): The storage class for the PVC. Defaults to 'local-storage'.
        service_type (str, optional): The type of Service to expose the image server. Options are 'ClusterIP', 'NodePort', or 'LoadBalancer'. Defaults to 'ClusterIP'.
        external_ip (str, optional): An external IP to assign to the Service if supported by the cluster (used with service_type 'ClusterIP' or 'LoadBalancer'). Defaults to None.

    Returns:
        dict: A dictionary with 'success' (bool), 'deployment_updated' (bool), 'service_updated' (bool), 'pvc_updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.image_server_present baremetal-operator-system service_type=LoadBalancer external_ip=192.168.1.100
    """
    try:
        deployment_updated = False
        service_updated = False
        pvc_updated = False
        deployment_exists = False
        service_exists = False
        pvc_exists = False
        deployment_matches = False
        service_matches = False
        pvc_matches = False
        message = f"Configuring Ironic image server in namespace {namespace}"

        _load_k8s_config()

        core_v1_api = client.CoreV1Api()
        apps_v1_api = client.AppsV1Api()

        # Step 1: Check if PVC exists
        try:
            pvc = core_v1_api.read_namespaced_persistent_volume_claim(
                name=pvc_name, namespace=namespace
            )
            pvc_exists = True
            current_pvc_spec = pvc.spec
            if (
                current_pvc_spec.resources.requests.get("storage", "") != storage_size
                or current_pvc_spec.storage_class_name != storage_class
            ):
                pvc_matches = False
            else:
                pvc_matches = True
        except ApiException as e:
            if e.status == 404:
                pvc_exists = False
                pvc_matches = False
            else:
                return {
                    "success": False,
                    "deployment_updated": False,
                    "service_updated": False,
                    "pvc_updated": False,
                    "message": f"Error fetching PVC {pvc_name}: {str(e)[:100]}...; {message}",
                }

        # Step 2: Create or update PVC if necessary
        if not pvc_exists or not pvc_matches:
            try:
                pvc_body = client.V1PersistentVolumeClaim(
                    metadata=client.V1ObjectMeta(name=pvc_name, namespace=namespace),
                    spec=client.V1PersistentVolumeClaimSpec(
                        access_modes=["ReadWriteOnce"],
                        resources=client.V1ResourceRequirements(
                            requests={"storage": storage_size}
                        ),
                        storage_class_name=storage_class,
                    ),
                )
                if pvc_exists:
                    core_v1_api.replace_namespaced_persistent_volume_claim(
                        name=pvc_name, namespace=namespace, body=pvc_body
                    )
                    pvc_updated = True
                    message += f"; PVC {pvc_name} updated"
                else:
                    core_v1_api.create_namespaced_persistent_volume_claim(
                        namespace=namespace, body=pvc_body
                    )
                    pvc_updated = True
                    message += f"; PVC {pvc_name} created"
            except ApiException as e:
                return {
                    "success": False,
                    "deployment_updated": False,
                    "service_updated": False,
                    "pvc_updated": False,
                    "message": f"Failed to create/update PVC {pvc_name}: {str(e)[:100]}...; {message}",
                }
        else:
            message += f"; PVC {pvc_name} already up-to-date"

        # Step 3: Check if Deployment exists
        try:
            deployment = apps_v1_api.read_namespaced_deployment(
                name=deployment_name, namespace=namespace
            )
            deployment_exists = True
            current_deployment_spec = deployment.spec
            current_image = (
                current_deployment_spec.template.spec.containers[0].image
                if current_deployment_spec.template.spec.containers
                else ""
            )
            current_command = (
                current_deployment_spec.template.spec.containers[0].command
                if current_deployment_spec.template.spec.containers
                else []
            )
            if current_image != image or current_command != [
                "python",
                "-m",
                "http.server",
                str(port),
                "--directory",
                storage_path,
            ]:
                deployment_matches = False
            else:
                deployment_matches = True
        except ApiException as e:
            if e.status == 404:
                deployment_exists = False
                deployment_matches = False
            else:
                return {
                    "success": False,
                    "deployment_updated": False,
                    "service_updated": False,
                    "pvc_updated": pvc_updated,
                    "message": f"Error fetching Deployment {deployment_name}: {str(e)[:100]}...; {message}",
                }

        # Step 4: Create or update Deployment if necessary
        if not deployment_exists or not deployment_matches:
            try:
                deployment_body = client.V1Deployment(
                    metadata=client.V1ObjectMeta(
                        name=deployment_name, namespace=namespace
                    ),
                    spec=client.V1DeploymentSpec(
                        replicas=1,
                        selector=client.V1LabelSelector(
                            match_labels={"app": "ironic-image-server"}
                        ),
                        template=client.V1PodTemplateSpec(
                            metadata=client.V1ObjectMeta(
                                labels={"app": "ironic-image-server"}
                            ),
                            spec=client.V1PodSpec(
                                containers=[
                                    client.V1Container(
                                        name="image-server",
                                        image=image,
                                        command=[
                                            "python",
                                            "-m",
                                            "http.server",
                                            str(port),
                                            "--directory",
                                            storage_path,
                                        ],
                                        ports=[
                                            client.V1ContainerPort(container_port=port)
                                        ],
                                        volume_mounts=[
                                            client.V1VolumeMount(
                                                name="images", mount_path=storage_path
                                            )
                                        ],
                                    )
                                ],
                                volumes=[
                                    client.V1Volume(
                                        name="images",
                                        persistent_volume_claim=client.V1PersistentVolumeClaimVolumeSource(
                                            claim_name=pvc_name
                                        ),
                                    )
                                ],
                            ),
                        ),
                    ),
                )
                if deployment_exists:
                    apps_v1_api.replace_namespaced_deployment(
                        name=deployment_name, namespace=namespace, body=deployment_body
                    )
                    deployment_updated = True
                    message += f"; Deployment {deployment_name} updated"
                else:
                    apps_v1_api.create_namespaced_deployment(
                        namespace=namespace, body=deployment_body
                    )
                    deployment_updated = True
                    message += f"; Deployment {deployment_name} created"
            except ApiException as e:
                return {
                    "success": False,
                    "deployment_updated": False,
                    "service_updated": False,
                    "pvc_updated": pvc_updated,
                    "message": f"Failed to create/update Deployment {deployment_name}: {str(e)[:100]}...; {message}",
                }
        else:
            message += f"; Deployment {deployment_name} already up-to-date"

        # Step 5: Check if Service exists
        try:
            service = core_v1_api.read_namespaced_service(
                name=service_name, namespace=namespace
            )
            service_exists = True
            current_service_spec = service.spec
            current_ports = (
                current_service_spec.ports if current_service_spec.ports else []
            )
            current_type = (
                current_service_spec.type if current_service_spec.type else "ClusterIP"
            )
            current_external_ips = (
                current_service_spec.external_i_ps
                if hasattr(current_service_spec, "external_i_ps")
                else []
            )
            if (
                len(current_ports) != 1
                or current_ports[0].port != port
                or current_ports[0].target_port != port
                or current_type != service_type
                or (external_ip and current_external_ips != [external_ip])
            ):
                service_matches = False
            else:
                service_matches = True
        except ApiException as e:
            if e.status == 404:
                service_exists = False
                service_matches = False
            else:
                return {
                    "success": False,
                    "deployment_updated": deployment_updated,
                    "service_updated": False,
                    "pvc_updated": pvc_updated,
                    "message": f"Error fetching Service {service_name}: {str(e)[:100]}...; {message}",
                }

        # Step 6: Create or update Service if necessary
        if not service_exists or not service_matches:
            try:
                service_body = client.V1Service(
                    metadata=client.V1ObjectMeta(
                        name=service_name, namespace=namespace
                    ),
                    spec=client.V1ServiceSpec(
                        selector={"app": "ironic-image-server"},
                        ports=[
                            client.V1ServicePort(
                                port=port, target_port=port, protocol="TCP"
                            )
                        ],
                        type=service_type,
                    ),
                )
                if external_ip and service_type in ["ClusterIP", "LoadBalancer"]:
                    service_body.spec.external_i_ps = [external_ip]
                    message += f"; Service {service_name} configured with external IP {external_ip}"
                if service_exists:
                    core_v1_api.replace_namespaced_service(
                        name=service_name, namespace=namespace, body=service_body
                    )
                    service_updated = True
                    message += f"; Service {service_name} updated"
                else:
                    core_v1_api.create_namespaced_service(
                        namespace=namespace, body=service_body
                    )
                    service_updated = True
                    message += f"; Service {service_name} created"
            except ApiException as e:
                return {
                    "success": False,
                    "deployment_updated": deployment_updated,
                    "service_updated": False,
                    "pvc_updated": pvc_updated,
                    "message": f"Failed to create/update Service {service_name}: {str(e)[:100]}...; {message}",
                }
        else:
            message += f"; Service {service_name} already up-to-date"

        return {
            "success": True
            if (
                deployment_updated
                or service_updated
                or pvc_updated
                or (deployment_matches and service_matches and pvc_matches)
            )
            else False,
            "deployment_updated": deployment_updated,
            "service_updated": service_updated,
            "pvc_updated": pvc_updated,
            "message": message,
        }
    except Exception as e:
        return {
            "success": False,
            "deployment_updated": False,
            "service_updated": False,
            "pvc_updated": False,
            "message": f"Image server operation error: {str(e)[:100]}...",
        }


def bmh_state(namespace, bmh_name, desired_state):
    """
    Check if a Bare Metal Host (BMH) object in Kubernetes is in the specified state.

    Args:
        namespace (str): The namespace of the Bare Metal Host resource in Kubernetes.
        bmh_name (str): The name of the Bare Metal Host resource.
        desired_state (str): The state to check for (e.g., 'provisioned', 'ready', 'error').

    Returns:
        dict: A dictionary with 'success' (bool), 'in_state' (bool), 'current_state' (str), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.bmh_state baremetal-operator-system compute-133-26 provisioned
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "metal3.io"
        version = "v1alpha1"
        plural = "baremetalhosts"

        # Check BMH status
        resource = custom_api.get_namespaced_custom_object(
            group=group,
            version=version,
            namespace=namespace,
            plural=plural,
            name=bmh_name,
        )
        status = resource.get("status", {})
        current_state = status.get("provisioning", {}).get("state", "unknown")

        return {
            "success": True,
            "in_state": current_state == desired_state,
            "current_state": current_state,
            "message": f"BMH {bmh_name} is in state: {current_state}. Checking for: {desired_state}",
        }

    except ApiException as e:
        if e.status == 404:
            return {
                "success": False,
                "in_state": False,
                "current_state": "not_found",
                "message": f"BMH {bmh_name} not found in namespace {namespace}",
            }
        return {
            "success": False,
            "in_state": False,
            "current_state": "error",
            "message": f"Kubernetes API error: {str(e)[:50]}...",
        }
    except Exception as e:
        return {
            "success": False,
            "in_state": False,
            "current_state": "error",
            "message": f"Error checking BMH state: {str(e)[:50]}...",
        }


def namespace_present(namespace):
    """
    Ensure that a Kubernetes namespace exists. If it does not exist, create it.

    Args:
        namespace (str): The name of the namespace to ensure exists.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.namespace_present my-namespace
    """
    try:
        _load_k8s_config()

        core_v1_api = client.CoreV1Api()
        exists = False
        updated = False

        # Check if namespace exists
        try:
            core_v1_api.read_namespace(name=namespace)
            exists = True
            message = f"Namespace {namespace} already exists"
        except ApiException as e:
            if e.status == 404:
                exists = False
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking namespace {namespace}: {str(e)[:50]}...",
                }

        # Create namespace if it does not exist
        if not exists:
            try:
                namespace_body = client.V1Namespace(
                    metadata=client.V1ObjectMeta(name=namespace)
                )
                core_v1_api.create_namespace(body=namespace_body)
                updated = True
                message = f"Namespace {namespace} created"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create namespace {namespace}: {str(e)[:50]}...",
                }

        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Namespace operation error: {str(e)[:50]}...",
        }


def ceph_cluster_present(namespace, cluster_name, spec):
    """
    Ensure that a CephCluster Custom Resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    Args:
        namespace (str): The namespace for the CephCluster resource.
        cluster_name (str): The name of the CephCluster resource.
        spec (dict): The specification for the CephCluster resource, including settings like cephVersion, storage, etc.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.ceph_cluster_present rook-ceph rook-ceph spec_dict
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "ceph.rook.io"
        version = "v1"
        plural = "cephclusters"

        exists = False
        updated = False
        matches = False

        # Check if CephCluster exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=cluster_name,
            )
            exists = True
            current_spec = resource.get("spec", {})
            # Simple check for spec equality (deep comparison could be added if needed)
            if current_spec == spec:
                matches = True
                message = f"CephCluster {cluster_name} in namespace {namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"CephCluster {cluster_name} in namespace {namespace} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"CephCluster {cluster_name} in namespace {namespace} does not exist"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking CephCluster {cluster_name}: {str(e)[:50]}...",
                }

        # Create or update CephCluster
        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "CephCluster",
            "metadata": {"name": cluster_name, "namespace": namespace},
            "spec": spec,
        }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=body,
                )
                updated = True
                message = f"CephCluster {cluster_name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create CephCluster {cluster_name}: {str(e)[:50]}...",
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if "metadata" in resource and "resourceVersion" in resource["metadata"]:
                    body["metadata"]["resourceVersion"] = resource["metadata"][
                        "resourceVersion"
                    ]
                custom_api.replace_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    name=cluster_name,
                    body=body,
                )
                updated = True
                message = f"CephCluster {cluster_name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update CephCluster {cluster_name}: {str(e)[:50]}...",
                }
        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"CephCluster operation error: {str(e)[:50]}...",
        }


def configmap_present(namespace, name, data, labels=None, annotations=None):
    """
    Ensure that a Kubernetes ConfigMap exists in the specified namespace. If it does not exist, create it.
    If it exists, update it if the data, labels, or annotations differ.

    Args:
        namespace (str): The namespace for the ConfigMap.
        name (str): The name of the ConfigMap.
        data (dict): The data to store in the ConfigMap (key-value pairs).
        labels (dict, optional): Labels to apply to the ConfigMap. Defaults to None.
        annotations (dict, optional): Annotations to apply to the ConfigMap. Defaults to None.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.configmap_present efk opensearch-dashboards-config "{'opensearch_dashboards.yml': 'content'}"
    """
    try:
        _load_k8s_config()

        core_v1_api = client.CoreV1Api()
        exists = False
        updated = False
        matches = False

        # Check if ConfigMap exists
        try:
            configmap = core_v1_api.read_namespaced_config_map(
                name=name, namespace=namespace
            )
            exists = True
            current_data = configmap.data or {}
            current_labels = configmap.metadata.labels or {}
            current_annotations = configmap.metadata.annotations or {}

            # Check if data, labels, or annotations match
            desired_labels = labels or {}
            desired_annotations = annotations or {}
            if (
                current_data == data
                and current_labels == desired_labels
                and current_annotations == desired_annotations
            ):
                matches = True
                message = f"ConfigMap {name} in namespace {namespace} already exists and matches desired state"
            else:
                matches = False
                message = f"ConfigMap {name} in namespace {namespace} exists but content differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"ConfigMap {name} in namespace {namespace} does not exist"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking ConfigMap {name}: {str(e)[:50]}...",
                }

        # Create or update ConfigMap
        configmap_body = client.V1ConfigMap(
            metadata=client.V1ObjectMeta(
                name=name,
                namespace=namespace,
                labels=labels or {},
                annotations=annotations or {},
            ),
            data=data,
        )

        if not exists:
            try:
                core_v1_api.create_namespaced_config_map(
                    namespace=namespace, body=configmap_body
                )
                updated = True
                message = f"ConfigMap {name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create ConfigMap {name}: {str(e)[:50]}...",
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if (
                    exists
                    and hasattr(configmap, "metadata")
                    and hasattr(configmap.metadata, "resource_version")
                ):
                    configmap_body.metadata.resource_version = (
                        configmap.metadata.resource_version
                    )
                core_v1_api.replace_namespaced_config_map(
                    name=name, namespace=namespace, body=configmap_body
                )
                updated = True
                message = f"ConfigMap {name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update ConfigMap {name}: {str(e)[:50]}...",
                }

        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"ConfigMap operation error: {str(e)[:50]}...",
        }


def service_present(
    namespace,
    service_name,
    service_type="LoadBalancer",
    selector=None,
    ports=None,
    annotations=None,
    external_ip=None,
):
    """
    Ensure that a Kubernetes Service is present in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    Args:
        namespace (str): The namespace for the Service.
        service_name (str): The name of the Service.
        service_type (str, optional): The type of Service ('ClusterIP', 'NodePort', 'LoadBalancer'). Defaults to 'LoadBalancer'.
        selector (dict, optional): The selector labels to match target pods. Defaults to None.
        ports (list, optional): List of port mappings (each with 'name', 'port', 'targetPort', 'protocol'). Defaults to None.
        annotations (dict, optional): Annotations to apply to the Service (e.g., for MetalLB). Defaults to None.
        external_ip (str, optional): An external IP to assign to the Service if supported. Defaults to None.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.service_present openstack openstack-public service_type=LoadBalancer selector="{'app.kubernetes.io/name': 'ingress-nginx'}" ports="[{ 'name': 'http', 'port': 80, 'targetPort': 80, 'protocol': 'TCP' }]" annotations="{'metallb.universe.tf/address-pool': 'default'}"
    """
    try:
        try:
            config.load_incluster_config()
            message = f"Loaded in-cluster config for Service {service_name} in namespace {namespace}"
        except config.ConfigException:
            config.load_kube_config()
            message = (
                f"Loaded kubeconfig for Service {service_name} in namespace {namespace}"
            )

        core_v1_api = client.CoreV1Api()
        exists = False
        updated = False
        matches = False

        # Default ports if none provided
        if ports is None:
            ports = [
                {"name": "http", "port": 80, "targetPort": 80, "protocol": "TCP"},
                {"name": "https", "port": 443, "targetPort": 443, "protocol": "TCP"},
            ]

        message += f"; Configuring as type {service_type}"

        # Check if Service exists
        try:
            service = core_v1_api.read_namespaced_service(
                name=service_name, namespace=namespace
            )
            exists = True
            current_spec = service.spec
            current_annotations = service.metadata.annotations or {}
            desired_annotations = annotations or {}
            desired_selector = selector or {}
            current_selector = current_spec.selector or {}
            desired_ports = ports
            current_ports = current_spec.ports if current_spec.ports else []
            current_type = current_spec.type if current_spec.type else "ClusterIP"
            current_external_ips = (
                current_spec.external_i_ps
                if hasattr(current_spec, "external_i_ps")
                else []
            )

            # Normalize ports for comparison (convert target_port to int if possible)
            normalized_current_ports = []
            for p in current_ports:
                port_dict = {
                    "name": p.name if p.name else "",
                    "port": p.port,
                    "targetPort": int(p.target_port)
                    if isinstance(p.target_port, (int, str))
                    and str(p.target_port).isdigit()
                    else p.target_port,
                    "protocol": p.protocol if p.protocol else "TCP",
                }
                normalized_current_ports.append(port_dict)

            normalized_desired_ports = []
            for p in desired_ports:
                port_dict = {
                    "name": p.get("name", ""),
                    "port": p["port"],
                    "targetPort": int(p["targetPort"])
                    if isinstance(p["targetPort"], str) and p["targetPort"].isdigit()
                    else p["targetPort"],
                    "protocol": p.get("protocol", "TCP"),
                }
                normalized_desired_ports.append(port_dict)

            # Check if spec and annotations match
            if (
                current_type == service_type
                and current_selector == desired_selector
                and normalized_current_ports == normalized_desired_ports
                and current_annotations == desired_annotations
                and (not external_ip or current_external_ips == [external_ip])
            ):
                matches = True
                message += f"; Service {service_name} already up-to-date"
            else:
                matches = False
                message += f"; Service {service_name} exists but spec or annotations differ (Type: {current_type} vs {service_type}, Selector: {current_selector} vs {desired_selector}, Ports: {normalized_current_ports} vs {normalized_desired_ports}, Annotations: {current_annotations} vs {desired_annotations}, External IP: {current_external_ips} vs {[external_ip] if external_ip else []})"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message += f"; Service {service_name} does not exist, will create"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error fetching Service {service_name}: Status: {e.status if hasattr(e, 'status') else 'Unknown'}, Reason: {e.reason if hasattr(e, 'reason') else 'Unknown'}, Body: {str(e.body)[:200] if hasattr(e, 'body') else 'N/A'}...; {message}",
                }

        # Build Service spec
        service_spec = client.V1ServiceSpec(
            selector=selector if selector else {},
            type=service_type,
            ports=[
                client.V1ServicePort(
                    name=p.get("name", ""),
                    port=p["port"],
                    target_port=p["targetPort"],
                    protocol=p.get("protocol", "TCP"),
                )
                for p in ports
            ],
        )
        if external_ip and service_type in ["ClusterIP", "LoadBalancer"]:
            service_spec.external_i_ps = [external_ip]
            message += f"; Configured with external IP {external_ip}"

        service_body = client.V1Service(
            metadata=client.V1ObjectMeta(
                name=service_name,
                namespace=namespace,
                annotations=annotations if annotations else {},
            ),
            spec=service_spec,
        )

        # Create or update Service if necessary
        if not exists:
            try:
                core_v1_api.create_namespaced_service(
                    namespace=namespace, body=service_body
                )
                updated = True
                message += f"; Service {service_name} created"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create Service {service_name}: Status: {e.status if hasattr(e, 'status') else 'Unknown'}, Reason: {e.reason if hasattr(e, 'reason') else 'Unknown'}, Body: {str(e.body)[:200] if hasattr(e, 'body') else 'N/A'}...; {message}",
                }
        elif not matches:
            try:
                core_v1_api.replace_namespaced_service(
                    name=service_name, namespace=namespace, body=service_body
                )
                updated = True
                message += f"; Service {service_name} updated"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update Service {service_name}: Status: {e.status if hasattr(e, 'status') else 'Unknown'}, Reason: {e.reason if hasattr(e, 'reason') else 'Unknown'}, Body: {str(e.body)[:200] if hasattr(e, 'body') else 'N/A'}...; {message}",
                }
        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Service operation error for {service_name}: {str(e)[:200]}...",
        }
    return ret


def node_label_present(namespace, node_name, labels):
    """
    Ensure that the specified labels are present on a Kubernetes node.
    If a label key exists with a different value, it will be updated. If it doesn't exist, it will be added.

    Args:
        namespace (str): The namespace is not used for node operations but kept for consistency.
        node_name (str): The name of the node to apply labels to.
        labels (dict): A dictionary of key-value pairs representing the labels to apply.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'message' (str), and 'changes' (dict).

    CLI Example:
        salt '*' kubernetes_k8s.node_label_present unused-namespace k8s-node-1 "{'key1': 'value1', 'key2': 'value2'}"
    """
    try:
        _load_k8s_config()

        core_v1_api = client.CoreV1Api()
        updated = False
        changes = {}

        # Retrieve the current node object
        node = core_v1_api.read_node(name=node_name)
        current_labels = node.metadata.labels or {}

        # Determine labels to update or add
        labels_to_apply = {}
        for key, value in labels.items():
            if key not in current_labels or current_labels[key] != value:
                labels_to_apply[key] = value
                changes[key] = {"old": current_labels.get(key, "not set"), "new": value}

        if labels_to_apply:
            # Update the node labels
            node.metadata.labels.update(labels_to_apply)
            core_v1_api.replace_node(name=node_name, body=node)
            updated = True
            message = f"Labels updated on node {node_name}"
        else:
            message = f"All specified labels already present on node {node_name}"

        return {
            "success": True,
            "updated": updated,
            "message": message,
            "changes": changes,
        }

    except ApiException as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Kubernetes API error while updating labels on node {node_name}: {str(e)[:50]}...",
            "changes": {},
        }
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Error updating labels on node {node_name}: {str(e)[:50]}...",
            "changes": {},
        }


def metallb_pool_present(
    namespace, pool_name, addresses, metallb_namespace="metallb-system"
):
    """
    Ensure that a MetalLB IPAddressPool Custom Resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    Args:
        namespace (str): The namespace for the IPAddressPool resource (unused, kept for consistency).
        pool_name (str): The name of the IPAddressPool resource.
        addresses (list): List of IP address ranges (e.g., ["10.150.1.43-10.150.1.50"]).
        metallb_namespace (str, optional): The namespace where MetalLB is installed. Defaults to 'metallb-system'.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.metallb_pool_present unused-namespace default ["10.150.1.43-10.150.1.50"]
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "metallb.io"
        version = "v1beta1"
        plural = "ipaddresspools"

        exists = False
        updated = False
        matches = False

        # Check if IPAddressPool exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=metallb_namespace,
                plural=plural,
                name=pool_name,
            )
            exists = True
            current_addresses = resource.get("spec", {}).get("addresses", [])
            if current_addresses == addresses:
                matches = True
                message = f"IPAddressPool {pool_name} in namespace {metallb_namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"IPAddressPool {pool_name} in namespace {metallb_namespace} exists but addresses differ"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"IPAddressPool {pool_name} in namespace {metallb_namespace} does not exist"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking IPAddressPool {pool_name}: {str(e)[:50]}...",
                }

        # Create or update IPAddressPool
        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "IPAddressPool",
            "metadata": {"name": pool_name, "namespace": metallb_namespace},
            "spec": {"addresses": addresses},
        }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=metallb_namespace,
                    plural=plural,
                    body=body,
                )
                updated = True
                message = f"IPAddressPool {pool_name} created in namespace {metallb_namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create IPAddressPool {pool_name}: {str(e)}",
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if "metadata" in resource and "resourceVersion" in resource["metadata"]:
                    body["metadata"]["resourceVersion"] = resource["metadata"][
                        "resourceVersion"
                    ]
                custom_api.replace_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=metallb_namespace,
                    plural=plural,
                    name=pool_name,
                    body=body,
                )
                updated = True
                message = f"IPAddressPool {pool_name} updated in namespace {metallb_namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update IPAddressPool {pool_name}: {str(e)}",
                }
        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"IPAddressPool operation error: {str(e)[:50]}...",
        }


def metallb_l2_advertisement_present(
    namespace, advertisement_name, pool_names, metallb_namespace="metallb-system"
):
    """
    Ensure that a MetalLB L2Advertisement Custom Resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    Args:
        namespace (str): The namespace for the L2Advertisement resource (unused, kept for consistency).
        advertisement_name (str): The name of the L2Advertisement resource.
        pool_names (list): List of IPAddressPool names to advertise.
        metallb_namespace (str, optional): The namespace where MetalLB is installed. Defaults to 'metallb-system'.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.metallb_l2_advertisement_present unused-namespace default-l2 ["default"]
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "metallb.io"
        version = "v1beta1"
        plural = "l2advertisements"

        exists = False
        updated = False
        matches = False

        # Check if L2Advertisement exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=metallb_namespace,
                plural=plural,
                name=advertisement_name,
            )
            exists = True
            current_pools = resource.get("spec", {}).get("ipAddressPools", [])
            if current_pools == pool_names:
                matches = True
                message = f"L2Advertisement {advertisement_name} in namespace {metallb_namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"L2Advertisement {advertisement_name} in namespace {metallb_namespace} exists but pools differ"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"L2Advertisement {advertisement_name} in namespace {metallb_namespace} does not exist"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking L2Advertisement {advertisement_name}: {str(e)[:50]}...",
                }

        # Create or update L2Advertisement
        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "L2Advertisement",
            "metadata": {"name": advertisement_name, "namespace": metallb_namespace},
            "spec": {"ipAddressPools": pool_names},
        }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=metallb_namespace,
                    plural=plural,
                    body=body,
                )
                updated = True
                message = f"L2Advertisement {advertisement_name} created in namespace {metallb_namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create L2Advertisement {advertisement_name}: {str(e)[:50]}...",
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if "metadata" in resource and "resourceVersion" in resource["metadata"]:
                    body["metadata"]["resourceVersion"] = resource["metadata"][
                        "resourceVersion"
                    ]
                custom_api.replace_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=metallb_namespace,
                    plural=plural,
                    name=advertisement_name,
                    body=body,
                )
                updated = True
                message = f"L2Advertisement {advertisement_name} updated in namespace {metallb_namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update L2Advertisement {advertisement_name}: {str(e)[:50]}...",
                }
        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"L2Advertisement operation error: {str(e)[:50]}...",
        }


def certmanager_issuer_present(namespace, issuer_name, issuer_kind="Issuer", spec=None):
    """
    Ensure that a Cert-Manager Issuer or ClusterIssuer resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    Args:
        namespace (str): The namespace for the Issuer resource. Use 'cluster-wide' for ClusterIssuer.
        issuer_name (str): The name of the Issuer or ClusterIssuer resource.
        issuer_kind (str, optional): The kind of issuer, either 'Issuer' or 'ClusterIssuer'. Defaults to 'Issuer'.
        spec (dict, optional): The specification for the Issuer resource. If not provided, a basic self-signed issuer spec will be used.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.certmanager_issuer_present cert-manager my-issuer spec_dict
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "cert-manager.io"
        version = "v1"
        plural = "issuers" if issuer_kind == "Issuer" else "clusterissuers"

        exists = False
        updated = False
        matches = False

        # Default spec for a self-signed issuer if none provided
        if spec is None:
            spec = {"selfSigned": {}}

        # Check if Issuer/ClusterIssuer exists
        try:
            if issuer_kind == "Issuer":
                resource = custom_api.get_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    name=issuer_name,
                )
            else:
                resource = custom_api.get_cluster_custom_object(
                    group=group, version=version, plural=plural, name=issuer_name
                )
            exists = True
            current_spec = resource.get("spec", {})
            if current_spec == spec:
                matches = True
                message = f"{issuer_kind} {issuer_name} already exists and matches desired spec in {namespace if issuer_kind == 'Issuer' else 'cluster-wide'}"
            else:
                matches = False
                message = f"{issuer_kind} {issuer_name} exists but spec differs in {namespace if issuer_kind == 'Issuer' else 'cluster-wide'}"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"{issuer_kind} {issuer_name} does not exist in {namespace if issuer_kind == 'Issuer' else 'cluster-wide'}"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking {issuer_kind} {issuer_name}: {str(e)[:50]}...",
                }

        # Create or update Issuer/ClusterIssuer
        body = {
            "apiVersion": f"{group}/{version}",
            "kind": issuer_kind,
            "metadata": {"name": issuer_name},
            "spec": spec,
        }
        if issuer_kind == "Issuer":
            body["metadata"]["namespace"] = namespace

        if not exists:
            try:
                if issuer_kind == "Issuer":
                    custom_api.create_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        body=body,
                    )
                else:
                    custom_api.create_cluster_custom_object(
                        group=group, version=version, plural=plural, body=body
                    )
                updated = True
                message = f"{issuer_kind} {issuer_name} created in {namespace if issuer_kind == 'Issuer' else 'cluster-wide'}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create {issuer_kind} {issuer_name}: {str(e)}...",
                }
        elif not matches:
            try:
                if "metadata" in resource and "resourceVersion" in resource["metadata"]:
                    body["metadata"]["resourceVersion"] = resource["metadata"][
                        "resourceVersion"
                    ]
                if issuer_kind == "Issuer":
                    custom_api.replace_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        name=issuer_name,
                        body=body,
                    )
                else:
                    custom_api.replace_cluster_custom_object(
                        group=group,
                        version=version,
                        plural=plural,
                        name=issuer_name,
                        body=body,
                    )
                updated = True
                message = f"{issuer_kind} {issuer_name} updated in {namespace if issuer_kind == 'Issuer' else 'cluster-wide'}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update {issuer_kind} {issuer_name}: {str(e)[:50]}...",
                }
        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"{issuer_kind} operation error: {str(e)[:50]}...",
        }


def ingress_present(
    name,
    namespace,
    hosts,
    tls=None,
    ingress_class_name=None,
    annotations=None,
    **kwargs,
):
    """
    Ensures that an Ingress resource is present in the specified namespace.

    Args:
        name (str): The name of the Ingress resource.
        namespace (str): The namespace in which the Ingress should exist.
        hosts (list): List of host configurations for the Ingress rules. Can be simple strings (hostnames)
                      or dictionaries with host, paths, path_type, service_name, and service_port.
        tls (list, optional): List of TLS configurations, each containing secretName and hosts.
        ingress_class_name (str, optional): The name of the IngressClass to use.
        annotations (dict, optional): Additional annotations for the Ingress.
        **kwargs: Additional arguments to pass to the Kubernetes API.

    Returns:
        dict: A dictionary containing the result of the operation.
    """
    ret = {"name": name, "result": None, "changes": {}, "comment": ""}

    try:
        # Load Kubernetes configuration
        _load_k8s_config()

        # Initialize Kubernetes API clients
        custom_api = client.CustomObjectsApi()
        group = "networking.k8s.io"
        version = "v1"
        plural = "ingresses"

        # Build the spec dictionary
        spec = {"rules": []}

        # Handle hosts and rules from pillar data
        for host_entry in hosts:
            if isinstance(host_entry, str):
                # Simple hostname string
                rule = {
                    "host": host_entry,
                    "http": {
                        "paths": [
                            {
                                "path": "/",
                                "pathType": "Prefix",
                                "backend": {
                                    "service": {
                                        "name": name,  # Fallback to ingress name if service name not specified
                                        "port": {
                                            "number": 389  # Default for LDAP
                                        },
                                    }
                                },
                            }
                        ]
                    },
                }
                spec["rules"].append(rule)
            elif isinstance(host_entry, dict):
                # Detailed configuration from pillar (e.g., ldap:ingress:hosts)
                host_name = host_entry.get("host", "")
                paths = host_entry.get("paths", [])
                rule = {"host": host_name, "http": {"paths": []}}
                for path_data in paths:
                    path = path_data.get("path", "/")
                    path_type = path_data.get("path_type", "Prefix")
                    service_name = path_data.get(
                        "service_name", name
                    )  # Fallback to ingress name
                    service_port = path_data.get(
                        "service_port", 389
                    )  # Default for LDAP
                    rule["http"]["paths"].append(
                        {
                            "path": path,
                            "pathType": path_type,
                            "backend": {
                                "service": {
                                    "name": service_name,
                                    "port": {"number": service_port},
                                }
                            },
                        }
                    )
                if rule["http"]["paths"]:  # Only add rule if paths are defined
                    spec["rules"].append(rule)

        # Add TLS configuration if provided
        if tls:
            spec["tls"] = tls

        # Add ingressClassName if provided
        if ingress_class_name:
            spec["ingressClassName"] = ingress_class_name

        # Build the desired Ingress resource
        desired_ingress = {
            "apiVersion": f"{group}/{version}",
            "kind": "Ingress",
            "metadata": {"name": name, "namespace": namespace},
            "spec": spec,
        }

        # Add annotations if provided
        if annotations:
            desired_ingress["metadata"]["annotations"] = annotations

        # Check if the Ingress already exists
        existing_ingress = None
        try:
            existing_ingress = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=name,
            )
        except ApiException as e:
            if e.status != 404:
                ret["result"] = False
                ret["comment"] = (
                    f"Error checking Ingress {name} in namespace {namespace}: {str(e)[:50]}..."
                )
                return ret

        if existing_ingress:
            # Update existing Ingress if it differs
            if (
                existing_ingress.get("spec", {}) != spec
                or existing_ingress.get("metadata", {}).get("annotations", {})
                != annotations
            ):
                try:
                    # Include resourceVersion to avoid conflicts
                    if (
                        "metadata" in existing_ingress
                        and "resourceVersion" in existing_ingress["metadata"]
                    ):
                        desired_ingress["metadata"]["resourceVersion"] = (
                            existing_ingress["metadata"]["resourceVersion"]
                        )
                    custom_api.replace_namespaced_custom_object(
                        group=group,
                        version=version,
                        namespace=namespace,
                        plural=plural,
                        name=name,
                        body=desired_ingress,
                    )
                    ret["result"] = True
                    ret["changes"] = {
                        "updated": f"Ingress {name} in namespace {namespace}"
                    }
                    ret["comment"] = f"Ingress {name} updated in namespace {namespace}."
                except ApiException as e:
                    ret["result"] = False
                    ret["comment"] = (
                        f"Failed to update Ingress {name} in namespace {namespace}: {str(e)[:50]}..."
                    )
            else:
                ret["result"] = True
                ret["comment"] = (
                    f"Ingress {name} already exists in namespace {namespace} with the desired configuration."
                )
        else:
            # Create new Ingress
            try:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=desired_ingress,
                )
                ret["result"] = True
                ret["changes"] = {"created": f"Ingress {name} in namespace {namespace}"}
                ret["comment"] = f"Ingress {name} created in namespace {namespace}."
            except ApiException as e:
                ret["result"] = False
                ret["comment"] = (
                    f"Failed to create Ingress {name} in namespace {namespace}: {str(e)[:50]}..."
                )
    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Error managing Ingress {name} in namespace {namespace}: {str(e)[:50]}..."
        )

    return ret


def certmanager_certificate_present(
    name,
    namespace,
    secret_name,
    issuer_name,
    issuer_kind,
    common_name,
    dns_names=None,
    ip_addresses=None,
    duration=None,
    renew_before=None,
    is_ca=False,
    subject=None,
    private_key=None,
    usages=None,
):
    """
    Ensure a cert-manager Certificate exists in the specified Kubernetes namespace with the given spec.

    Args:
        name (str): The name of the Certificate resource.
        namespace (str): The Kubernetes namespace for the Certificate.
        secret_name (str): The name of the Secret where the certificate will be stored.
        issuer_name (str): The name of the Issuer or ClusterIssuer to use.
        issuer_kind (str): The kind of the Issuer (e.g., 'Issuer' or 'ClusterIssuer').
        common_name (str): The common name (CN) for the certificate.
        dns_names (list, optional): List of DNS names (SANs) for the certificate. Defaults to None.
        ip_addresses (list, optional): List of IP addresses (SANs) for the certificate. Defaults to None.
        duration (str, optional): Duration of the certificate validity (e.g., '2160h'). Defaults to None.
        renew_before (str, optional): Time before expiration to renew the certificate (e.g., '360h'). Defaults to None.
        is_ca (bool, optional): If True, the certificate will be marked as a CA certificate. Defaults to False.
        subject (dict, optional): Subject block (organizations, organizationalUnits, countries, etc.).
        private_key (dict, optional): Private-key settings (algorithm, size, encoding).
        usages (list, optional): Extended key usages.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'message' (str), and 'resource' (dict, if created/updated).

    CLI Example:
        salt '*' kubernetes_k8s.certmanager_certificate_present ldap-tls-cert ldap tls-cert selfsigned-issuer ClusterIssuer ldap.example.com dns_names="['ldap.example.com']" duration="2160h" is_ca=True
    """
    try:
        # Load Kubernetes configuration (in-cluster or from kubeconfig)
        __salt__["log.debug"](
            "Attempting to load Kubernetes configuration for certmanager_certificate_present"
        )
        try:
            config.load_incluster_config()
            __salt__["log.debug"](
                "Successfully loaded in-cluster Kubernetes configuration"
            )
        except config.ConfigException as e:
            __salt__["log.debug"](
                f"Failed to load in-cluster config, falling back to kubeconfig: {str(e)}"
            )
            config.load_kube_config()
            __salt__["log.debug"]("Successfully loaded kubeconfig")

        custom_api = client.CustomObjectsApi()
        __salt__["log.debug"](
            "Initialized CustomObjectsApi client for cert-manager operations"
        )

        # Construct the spec for the Certificate
        spec = {
            "secretName": secret_name,
            "issuerRef": {"name": issuer_name, "kind": issuer_kind},
            "commonName": common_name,
        }
        if dns_names:
            spec["dnsNames"] = dns_names
        if ip_addresses:
            spec["ipAddresses"] = ip_addresses
        if duration:
            spec["duration"] = duration
        if renew_before:
            spec["renewBefore"] = renew_before
        if is_ca:
            spec["isCA"] = True
        if subject:
            spec["subject"] = subject
        if private_key:
            spec["privateKey"] = private_key
        if usages:
            spec["usages"] = usages

        # Define the full Certificate object
        cert_body = {
            "apiVersion": "cert-manager.io/v1",
            "kind": "Certificate",
            "metadata": {"name": name, "namespace": namespace},
            "spec": spec,
        }

        # Check if Certificate already exists
        group, version = "cert-manager.io", "v1"
        plural = "certificates"
        __salt__["log.debug"](
            f"Checking if Certificate {name} exists in namespace {namespace}"
        )
        try:
            existing_cert = custom_api.get_namespaced_custom_object(
                group, version, namespace, plural, name
            )
            __salt__["log.debug"](
                f"Found existing Certificate {name} in namespace {namespace}"
            )
            # Compare spec fields to determine if update is needed
            existing_spec = existing_cert.get("spec", {})
            if existing_spec != spec:
                __salt__["log.debug"](
                    f"Spec for Certificate {name} differs, updating resource"
                )
                # Handle resourceVersion for cert-manager update
                cert_body, rv_message = handle_certmanager_resource_version(
                    body=cert_body,
                    existing_resource=existing_cert,
                    api_instance=custom_api,
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    name=name,
                )
                __salt__["log.debug"](
                    f"Handled resource version for update: {rv_message}"
                )
                # Update the Certificate
                updated_cert = custom_api.replace_namespaced_custom_object(
                    group, version, namespace, plural, name, cert_body
                )
                __salt__["log.debug"](
                    f"Successfully updated Certificate {name} in namespace {namespace}"
                )
                return {
                    "success": True,
                    "updated": True,
                    "message": f"Certificate {name} updated in namespace {namespace}. {rv_message}",
                    "resource": updated_cert,
                }
            __salt__["log.debug"](f"Certificate {name} spec matches, no update needed")
            return {
                "success": True,
                "updated": False,
                "message": f"Certificate {name} already exists in namespace {namespace} with matching spec.",
                "resource": existing_cert,
            }
        except ApiException as e:
            if e.status == 404:
                __salt__["log.debug"](
                    f"Certificate {name} not found in namespace {namespace}, creating it"
                )
                # Certificate does not exist, create it
                created_cert = custom_api.create_namespaced_custom_object(
                    group, version, namespace, plural, cert_body
                )
                __salt__["log.debug"](
                    f"Successfully created Certificate {name} in namespace {namespace}"
                )
                return {
                    "success": True,
                    "updated": True,
                    "message": f"Certificate {name} created in namespace {namespace}.",
                    "resource": created_cert,
                }
            __salt__["log.error"](
                f"ApiException while managing Certificate {name} in namespace {namespace}: {str(e)}"
            )
            return {
                "success": False,
                "updated": False,
                "message": f"ApiException: Failed to manage Certificate {name} in namespace {namespace}: {str(e)}",
            }
        except Exception as e:
            __salt__["log.error"](
                f"Unexpected error while managing Certificate {name} in namespace {namespace}: {str(e)}"
            )
            return {
                "success": False,
                "updated": False,
                "message": f"Unexpected error managing Certificate {name} in namespace {namespace}: {str(e)}",
            }
    except Exception as e:
        __salt__["log.error"](
            f"Initialization error for Certificate {name} in namespace {namespace}: {str(e)}"
        )
        return {
            "success": False,
            "updated": False,
            "message": f"Initialization error for Certificate {name} in namespace {namespace}: {str(e)}",
        }


def cnpg_cluster_present(namespace, cluster_name, spec):
    """
    Ensure that a CloudNativePG Cluster Custom Resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.

    Args:
        namespace (str): The namespace for the Cluster resource.
        cluster_name (str): The name of the Cluster resource.
        spec (dict): The specification for the Cluster resource, including instances, imageName, storage, etc.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.cnpg_cluster_present cnpg-system my-cluster spec_dict
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "postgresql.cnpg.io"
        version = "v1"
        plural = "clusters"

        exists = False
        updated = False
        matches = False

        # Check if Cluster exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=cluster_name,
            )
            exists = True
            current_spec = resource.get("spec", {})
            if current_spec == spec:
                matches = True
                message = f"Cluster {cluster_name} in namespace {namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"Cluster {cluster_name} in namespace {namespace} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = (
                    f"Cluster {cluster_name} in namespace {namespace} does not exist"
                )
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking Cluster {cluster_name}: {str(e)[:50]}...",
                }

        # Create or update Cluster
        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "Cluster",
            "metadata": {"name": cluster_name, "namespace": namespace},
            "spec": spec,
        }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=body,
                )
                updated = True
                message = f"Cluster {cluster_name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create Cluster {cluster_name}: {str(e)}...",
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if "metadata" in resource and "resourceVersion" in resource["metadata"]:
                    body["metadata"]["resourceVersion"] = resource["metadata"][
                        "resourceVersion"
                    ]
                custom_api.replace_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    name=cluster_name,
                    body=body,
                )
                updated = True
                message = f"Cluster {cluster_name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update Cluster {cluster_name}: {str(e)[:50]}...",
                }
        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Cluster operation error: {str(e)[:50]}...",
        }


def opensearch_cluster_present(namespace, cluster_name, spec):
    """
    Ensure that an OpenSearchCluster Custom Resource exists in the specified
    namespace. If it does not exist, create it. If it exists, update it if
    necessary.

    Args:
        namespace (str): The namespace for the OpenSearchCluster resource.
        cluster_name (str): The name of the OpenSearchCluster resource.
        spec (dict): The specification for the OpenSearchCluster resource.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic_k8s.opensearch_cluster_present efk my-cluster spec_dict
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "opensearch.org"
        version = "v1"
        plural = "opensearchclusters"

        exists = False
        updated = False
        matches = False

        # Check if OpenSearchCluster exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=cluster_name,
            )
            exists = True
            current_spec = resource.get("spec", {})
            if current_spec == spec:
                matches = True
                message = f"OpenSearchCluster {cluster_name} in namespace {namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"OpenSearchCluster {cluster_name} in namespace {namespace} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = (
                    f"OpenSearchCluster {cluster_name} in namespace {namespace} does not exist"
                )
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking OpenSearchCluster {cluster_name}: {str(e)[:50]}...",
                }

        # Create or update OpenSearchCluster
        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "OpenSearchCluster",
            "metadata": {"name": cluster_name, "namespace": namespace},
            "spec": spec,
        }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=body,
                )
                updated = True
                message = f"OpenSearchCluster {cluster_name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create OpenSearchCluster {cluster_name}: {str(e)}...",
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if "metadata" in resource and "resourceVersion" in resource["metadata"]:
                    body["metadata"]["resourceVersion"] = resource["metadata"][
                        "resourceVersion"
                    ]
                custom_api.replace_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    name=cluster_name,
                    body=body,
                )
                updated = True
                message = f"OpenSearchCluster {cluster_name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update OpenSearchCluster {cluster_name}: {str(e)[:50]}...",
                }
        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"OpenSearchCluster operation error: {str(e)[:50]}...",
        }


def get_secret_value(namespace, secret_name, key, default=None):
    """
    Retrieve a single decoded value from a Kubernetes Secret.

    Useful for reading credentials that are generated/managed outside of Salt
    (e.g. an admin password auto-generated by an operator) directly from the
    cluster instead of duplicating them in pillar.

    Args:
        namespace (str): Namespace containing the secret.
        secret_name (str): Name of the secret.
        key (str): Key within the secret's data/stringData to retrieve.
        default: Value to return if the secret or key does not exist, or on error.

    Returns:
        str: The decoded value, or `default` if not found.

    CLI Example:
        salt '*' kinetic_k8s.get_secret_value efk opensearch-admin-password password
    """
    try:
        _load_k8s_config()
        core_v1_api = client.CoreV1Api()
        secret = core_v1_api.read_namespaced_secret(
            name=secret_name, namespace=namespace
        )
        data = _decode_k8s_secret(secret)
        return data.get(key, default)
    except ApiException as e:
        if e.status == 404:
            return default
        return default
    except Exception:
        return default


def secret_present(
    namespace, secret_name, data, secret_type="Opaque", labels=None, annotations=None
):
    """
    Ensure that a Kubernetes Secret exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if the data, labels, or annotations differ.

    Args:
        namespace (str): The namespace for the Secret.
        secret_name (str): The name of the Secret.
        data (dict): The data to store in the Secret (key-value pairs). Values will be base64 encoded.
        secret_type (str, optional): The type of Secret (e.g., 'Opaque', 'kubernetes.io/tls'). Defaults to 'Opaque'.
        labels (dict, optional): Labels to apply to the Secret. Defaults to None.
        annotations (dict, optional): Annotations to apply to the Secret. Defaults to None.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.secret_present my-namespace my-secret "{'key1': 'value1', 'key2': 'value2'}"
    """
    try:
        _load_k8s_config()

        core_v1_api = client.CoreV1Api()
        exists = False
        updated = False
        matches = False

        # Check if Secret exists
        try:
            secret = core_v1_api.read_namespaced_secret(
                name=secret_name, namespace=namespace
            )
            exists = True
            current_data = secret.data or {}
            current_labels = secret.metadata.labels or {}
            current_annotations = secret.metadata.annotations or {}
            current_type = secret.type or "Opaque"

            # Decode current data from base64 for comparison
            decoded_current_data = {}
            for k, v in current_data.items():
                try:
                    decoded_current_data[k] = base64.b64decode(v).decode("utf-8")
                except Exception:
                    decoded_current_data[k] = (
                        v  # If decoding fails, keep as is for comparison
                    )

            desired_labels = labels or {}
            desired_annotations = annotations or {}
            if (
                decoded_current_data == data
                and current_labels == desired_labels
                and current_annotations == desired_annotations
                and current_type == secret_type
            ):
                matches = True
                message = f"Secret {secret_name} in namespace {namespace} already exists and matches desired state"
            else:
                matches = False
                message = f"Secret {secret_name} in namespace {namespace} exists but content differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = (
                    f"Secret {secret_name} in namespace {namespace} does not exist"
                )
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking Secret {secret_name}: {str(e)[:50]}...",
                }

        # Encode data to base64 for Secret creation/update
        encoded_data = {}
        for k, v in data.items():
            if isinstance(v, str):
                encoded_data[k] = base64.b64encode(v.encode("utf-8")).decode("utf-8")
            else:
                encoded_data[k] = base64.b64encode(str(v).encode("utf-8")).decode(
                    "utf-8"
                )

        # Create or update Secret
        secret_body = client.V1Secret(
            metadata=client.V1ObjectMeta(
                name=secret_name,
                namespace=namespace,
                labels=labels or {},
                annotations=annotations or {},
            ),
            data=encoded_data,
            type=secret_type,
        )

        if not exists:
            try:
                core_v1_api.create_namespaced_secret(
                    namespace=namespace, body=secret_body
                )
                updated = True
                message = f"Secret {secret_name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create Secret {secret_name}: {str(e)}...",
                }
        elif not matches:
            try:
                core_v1_api.replace_namespaced_secret(
                    name=secret_name, namespace=namespace, body=secret_body
                )
                updated = True
                message = f"Secret {secret_name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update Secret {secret_name}: {str(e)}...",
                }

        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Secret operation error: {str(e)}...",
        }


def keycloak_cluster_present(
    namespace,
    hostname,
    cluster_name,
    start_optimized=False,
    instances=1,
    image=None,
    db_vendor="postgres",
    db_host=None,
    db_port=5432,
    db_name=None,
    db_user_name_secret_name=None,
    db_user_name_secret_key="username",
    db_password_secret_name=None,
    db_password_secret_key="password",
    ingress_enabled=False,
    proxy_headers=None,
    tls_secret=None,
    truststores=None,
):
    """
    Ensure a Keycloak Cluster exists in the specified Kubernetes namespace with the given configuration.
    If the resource exists and needs updating, it will be deleted and recreated due to update limitations.

    Args:
        namespace (str): The Kubernetes namespace for the Keycloak Cluster.
        hostname (str): The hostname for the Keycloak instance.
        cluster_name (str): The name of the Keycloak Cluster resource.
        start_optimized (bool, optional): Whether to start Keycloak in optimized mode. Defaults to False.
        instances (int, optional): Number of Keycloak instances. Defaults to 1.
        image (str, optional): Docker image for Keycloak. Defaults to None (uses operator default).
        db_vendor (str, optional): Database vendor (e.g., 'postgres'). Defaults to 'postgres'.
        db_host (str, optional): Database host. Defaults to None.
        db_port (int, optional): Database port. Defaults to 5432.
        db_name (str, optional): Database name. Defaults to None.
        db_user_name_secret_name (str, optional): Secret name for database username. Defaults to None.
        db_user_name_secret_key (str, optional): Key in the secret for username. Defaults to 'username'.
        db_password_secret_name (str, optional): Secret name for database password. Defaults to None.
        db_password_secret_key (str, optional): Key in the secret for password. Defaults to 'password'.
        ingress_enabled (bool, optional): Whether to enable ingress. Defaults to False.
        proxy_headers (str, optional): Proxy headers configuration (e.g., 'forwarded'). Defaults to None.
        tls_secret (str, optional): Name of the TLS secret for HTTPS. Defaults to None.
        truststores (dict, optional): Dictionary mapping truststore names to configurations with secret names. Defaults to None.
            Example: {'my-truststore': {'secret': {'name': 'my-secret'}}}

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'message' (str), and 'resource' (dict, if created/updated).

    CLI Example:
        salt '*' kubernetes_k8s.keycloak_cluster_present keycloak keycloak.example.com keycloak-cluster instances=2 truststores="{'my-truststore': {'secret': {'name': 'my-secret'}}}"
    """
    try:
        _load_k8s_config()
        custom_api = client.CustomObjectsApi()

        # Construct the spec for the Keycloak Cluster
        spec = {
            "instances": instances,
            "startOptimized": start_optimized,
            "hostname": {
                "hostname": hostname  # Structured as an object per error message requirement
            },
            "http": {
                "httpEnabled": True,
            },
        }
        if tls_secret:
            spec["http"]["tlsSecret"] = tls_secret
        if image:
            spec["image"] = image
        if db_vendor and db_host and db_name:
            spec["db"] = {
                "vendor": db_vendor,
                "host": db_host,
                "port": db_port,
                "database": db_name,
            }
            if db_user_name_secret_name:
                spec["db"]["usernameSecret"] = {
                    "name": db_user_name_secret_name,
                    "key": db_user_name_secret_key,
                }
            if db_password_secret_name:
                spec["db"]["passwordSecret"] = {
                    "name": db_password_secret_name,
                    "key": db_password_secret_key,
                }
        if proxy_headers:
            spec["proxy"] = {"headers": proxy_headers}
        if truststores:
            spec["truststores"] = truststores

        # Define the full Keycloak Cluster object
        keycloak_body = {
            "apiVersion": "k8s.keycloak.org/v2alpha1",
            "kind": "Keycloak",
            "metadata": {"name": cluster_name, "namespace": namespace},
            "spec": spec,
        }

        # Check if Keycloak Cluster already exists
        group, version = "k8s.keycloak.org", "v2alpha1"
        plural = "keycloaks"
        try:
            existing_keycloak = custom_api.get_namespaced_custom_object(
                group, version, namespace, plural, cluster_name
            )
            # Compare spec fields to determine if update is needed
            existing_spec = existing_keycloak.get("spec", {})
            existing_http = existing_spec.get("http", {})
            existing_db = existing_spec.get("db", {})
            # Ensure truststores comparison handles None explicitly
            existing_truststores = existing_spec.get("truststores", {})
            truststores_differs = (
                (truststores != existing_truststores)
                and not (truststores is None and existing_truststores == {})
                and not (existing_truststores is None and truststores == {})
            )
            if (
                existing_spec.get("instances") != instances
                or existing_spec.get("hostname", {}).get("hostname") != hostname
                or existing_spec.get("startOptimized") != start_optimized
                or (image and existing_spec.get("image") != image)
                or (db_host and existing_db.get("host") != db_host)
                or (db_name and existing_db.get("database") != db_name)
                or (db_vendor and existing_db.get("vendor") != db_vendor)
                or (db_port and existing_db.get("port") != db_port)
                or (
                    db_user_name_secret_name
                    and existing_db.get("usernameSecret", {}).get("name")
                    != db_user_name_secret_name
                )
                or (
                    db_password_secret_name
                    and existing_db.get("passwordSecret", {}).get("name")
                    != db_password_secret_name
                )
                or (
                    proxy_headers
                    and existing_spec.get("proxy", {}).get("headers") != proxy_headers
                )
                or (tls_secret and existing_http.get("tlsSecret") != tls_secret)
                or existing_http.get("httpEnabled", False) != True
                or truststores_differs
            ):
                # Since updates are not supported, delete the existing resource first
                try:
                    custom_api.delete_namespaced_custom_object(
                        group, version, namespace, plural, cluster_name
                    )
                    # Wait briefly to ensure deletion is processed (Kubernetes eventual consistency)
                    import time

                    time.sleep(5)
                    # Recreate the Keycloak Cluster with the updated spec
                    created_keycloak = custom_api.create_namespaced_custom_object(
                        group, version, namespace, plural, keycloak_body
                    )
                    return {
                        "success": True,
                        "updated": True,
                        "message": f"Keycloak Cluster {cluster_name} deleted and recreated in namespace {namespace} due to spec changes.",
                        "resource": created_keycloak,
                    }
                except ApiException as delete_e:
                    return {
                        "success": False,
                        "updated": False,
                        "message": f"Failed to delete and recreate Keycloak Cluster {cluster_name} in namespace {namespace}: {str(delete_e)[:200]}...",
                        "resource": {},
                    }
            return {
                "success": True,
                "updated": False,
                "message": f"Keycloak Cluster {cluster_name} already exists in namespace {namespace} with matching spec.",
                "resource": existing_keycloak,
            }
        except ApiException as e:
            if e.status == 404:
                # Keycloak Cluster does not exist, create it
                try:
                    created_keycloak = custom_api.create_namespaced_custom_object(
                        group, version, namespace, plural, keycloak_body
                    )
                    return {
                        "success": True,
                        "updated": True,
                        "message": f"Keycloak Cluster {cluster_name} created in namespace {namespace}.",
                        "resource": created_keycloak,
                    }
                except ApiException as create_e:
                    return {
                        "success": False,
                        "updated": False,
                        "message": f"Failed to create Keycloak Cluster {cluster_name} in namespace {namespace}. Ensure Keycloak Operator is installed and spec is valid: {str(create_e)[:200]}...",
                        "resource": {},
                    }
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to manage Keycloak Cluster {cluster_name} in namespace {namespace}: {str(e)[:200]}...",
                    "resource": {},
                }
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Error managing Keycloak Cluster {cluster_name} in namespace {namespace}: {str(e)[:100]}...",
            "resource": {},
        }


def certificate_present(
    namespace,
    certificate_name,
    common_name,
    email_address,
    dns_name=None,
    duration="2160h",
    renew_before="360h",
    issuer_ref="self-signed",
):
    """
    Ensure that a Cert-Manager Certificate resource exists in the specified namespace.
    If it does not exist, create it. If it exists, update it if necessary.
    Also checks if the associated Secret resource exists.

    Args:
        namespace (str): The namespace for the Certificate resource.
        certificate_name (str): The name of the Certificate resource.
        common_name (str): The Common Name (CN) for the certificate.
        email_address (str): Ignored. Previously used for the certificate subject, now omitted for ACME compatibility.
        dns_name (str, optional): DNS name for the certificate. Defaults to None.
        duration (str, optional): Duration of the certificate validity. Defaults to "2160h" (90 days).
        renew_before (str, optional): Time before expiration to renew the certificate. Defaults to "360h" (15 days).
        issuer_ref (str or dict/list, optional): Reference to the issuer. Can be a string (name only), or a dict/list with 'name' and 'kind'. Defaults to "self-signed".

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'secret_exists' (bool), and 'message' (str).

    CLI Example:
        salt '*' kubernetes_k8s.certificate_present my-namespace my-cert example.com admin@example.com dns_name=www.example.com issuer_ref="{'name': 'letsencrypt-prod', 'kind': 'ClusterIssuer'}"
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        core_v1_api = client.CoreV1Api()
        group = "cert-manager.io"
        version = "v1"
        plural = "certificates"

        exists = False
        updated = False
        matches = False
        secret_exists = False

        # Parse issuer_ref to extract name and kind
        issuer_name = "self-signed"
        issuer_kind = "Issuer"
        if isinstance(issuer_ref, (dict, list)):
            if isinstance(issuer_ref, dict):
                issuer_name = issuer_ref.get("name", "self-signed")
                issuer_kind = issuer_ref.get("kind", "Issuer")
            else:  # list format as in pillar example
                for item in issuer_ref:
                    if "name" in item:
                        issuer_name = item["name"]
                    if "kind" in item:
                        issuer_kind = item["kind"]
        else:
            issuer_name = issuer_ref

        # Ensure dnsNames includes common_name if applicable for ACME
        dns_names = [common_name]
        if dns_name and dns_name not in dns_names:
            dns_names.append(dns_name)

        # Build the spec for Certificate (email_address is ignored for ACME compatibility)
        spec = {
            "secretName": certificate_name,
            "commonName": common_name,
            "dnsNames": dns_names,
            "duration": duration,
            "renewBefore": renew_before,
            "issuerRef": {"name": issuer_name, "kind": issuer_kind},
        }

        # Check if Certificate exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=certificate_name,
            )
            exists = True
            current_spec = resource.get("spec", {})
            if current_spec == spec:
                matches = True
                message = f"Certificate {certificate_name} in namespace {namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"Certificate {certificate_name} in namespace {namespace} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"Certificate {certificate_name} in namespace {namespace} does not exist"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "secret_exists": False,
                    "message": f"Error checking Certificate {certificate_name}: {str(e)[:50]}...",
                }

        # Check if associated Secret exists
        try:
            core_v1_api.read_namespaced_secret(
                name=certificate_name, namespace=namespace
            )
            secret_exists = True
        except ApiException as e:
            if e.status == 404:
                secret_exists = False
            else:
                return {
                    "success": False,
                    "updated": False,
                    "secret_exists": False,
                    "message": f"Error checking Secret {certificate_name}: {str(e)[:50]}...",
                }

        # Create or update Certificate
        body = {
            "apiVersion": f"{group}/{version}",
            "kind": "Certificate",
            "metadata": {"name": certificate_name, "namespace": namespace},
            "spec": spec,
        }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=body,
                )
                updated = True
                message = (
                    f"Certificate {certificate_name} created in namespace {namespace}"
                )
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "secret_exists": secret_exists,
                    "message": f"Failed to create Certificate {certificate_name}: {str(e)[:50]}...",
                }
        elif not matches:
            try:
                # Include resourceVersion if updating to avoid conflicts
                if "metadata" in resource and "resourceVersion" in resource["metadata"]:
                    body["metadata"]["resourceVersion"] = resource["metadata"][
                        "resourceVersion"
                    ]
                custom_api.replace_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    name=certificate_name,
                    body=body,
                )
                updated = True
                message = (
                    f"Certificate {certificate_name} updated in namespace {namespace}"
                )
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "secret_exists": secret_exists,
                    "message": f"Failed to update Certificate {certificate_name}: {str(e)[:50]}...",
                }
        return {
            "success": True,
            "updated": updated,
            "secret_exists": secret_exists,
            "message": message,
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "secret_exists": False,
            "message": f"Certificate operation error: {str(e)[:50]}...",
        }


def pvc_present(
    name, namespace, storage_class, storage_size, access_modes=None, selector=None
):
    """
    Ensure a PersistentVolumeClaim (PVC) exists in the specified Kubernetes namespace.

    Args:
        name (str): The name of the PVC to create or update.
        namespace (str): The Kubernetes namespace for the PVC.
        storage_class (str): The storage class name to use for the PVC.fs
        storage_size (str): The storage capacity to request (e.g., '5Gi', '10Gi').
        access_modes (list, optional): List of access modes (e.g., ['ReadWriteOnce']). Defaults to ['ReadWriteOnce'].
        selector (dict, optional): Label selector to match a specific PV (e.g., {'matchLabels': {'type': 'local'}}). Defaults to None.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'message' (str), and 'resource' (dict, if created/updated).

    CLI Example:
        salt '*' kubernetes_k8s.pvc_present my-pvc my-namespace local-storage 5Gi access_modes="['ReadWriteOnce']"
    """
    try:
        _load_k8s_config()
        v1_api = client.CoreV1Api()

        # Default access modes if not provided
        if access_modes is None:
            access_modes = ["ReadWriteOnce"]

        # Define the PVC spec
        pvc_spec = client.V1PersistentVolumeClaimSpec(
            storage_class_name=storage_class,
            resources=client.V1ResourceRequirements(requests={"storage": storage_size}),
            access_modes=access_modes,
        )
        if selector:
            pvc_spec.selector = client.V1LabelSelector(**selector)

        # Define the full PVC object
        pvc_body = client.V1PersistentVolumeClaim(
            api_version="v1",
            kind="PersistentVolumeClaim",
            metadata=client.V1ObjectMeta(name=name, namespace=namespace),
            spec=pvc_spec,
        )

        # Check if PVC already exists
        try:
            existing_pvc = v1_api.read_namespaced_persistent_volume_claim(
                name=name, namespace=namespace
            )
            # Compare and update if necessary (simplified check for storage size and class)
            existing_spec = existing_pvc.spec
            if (
                existing_spec.storage_class_name != storage_class
                or existing_spec.resources.requests.get("storage") != storage_size
            ):
                # Update the PVC (note: some fields like storage size may require recreation in older K8s versions)
                updated_pvc = v1_api.replace_namespaced_persistent_volume_claim(
                    name=name, namespace=namespace, body=pvc_body
                )
                return {
                    "success": True,
                    "updated": True,
                    "message": f"PVC {name} updated in namespace {namespace}.",
                    "resource": updated_pvc.to_dict(),
                }
            return {
                "success": True,
                "updated": False,
                "message": f"PVC {name} already exists in namespace {namespace} with matching spec.",
                "resource": existing_pvc.to_dict(),
            }
        except ApiException as e:
            if e.status == 404:
                # PVC does not exist, create it
                created_pvc = v1_api.create_namespaced_persistent_volume_claim(
                    namespace=namespace, body=pvc_body
                )
                return {
                    "success": True,
                    "updated": True,
                    "message": f"PVC {name} created in namespace {namespace}.",
                    "resource": created_pvc.to_dict(),
                }
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to manage PVC {name} in namespace {namespace}: {str(e)[:100]}...",
                    "resource": {},
                }
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Error managing PVC {name} in namespace {namespace}: {str(e)[:100]}...",
            "resource": {},
        }


def job_cleanup(namespace=None):
    """
    Clean up completed jobs (such as pods) in the specified Kubernetes namespace (or all namespaces if none provided)
    that have a status.phase of Succeeded.

    Args:
        namespace (str, optional): The Kubernetes namespace to target. If None, targets all namespaces.

    Returns:
        dict: A dictionary with 'success' (bool), 'deleted_items' (list), and 'message' (str).
    """
    try:
        _load_k8s_config()
        v1_api = client.CoreV1Api()

        # Field selector for pods with status.phase==Succeeded
        field_selector = "status.phase==Succeeded"

        if namespace:
            # Get pods in the specified namespace
            pod_list = v1_api.list_namespaced_pod(
                namespace=namespace, field_selector=field_selector
            )
        else:
            # Get pods in all namespaces
            pod_list = v1_api.list_pod_for_all_namespaces(field_selector=field_selector)

        deleted_pods = []
        for pod in pod_list.items:
            pod_name = pod.metadata.name
            pod_namespace = pod.metadata.namespace
            try:
                v1_api.delete_namespaced_pod(
                    name=pod_name,
                    namespace=pod_namespace,
                    body=client.V1DeleteOptions(),
                )
                deleted_pods.append(f"{pod_name} in {pod_namespace}")
            except ApiException as e:
                return {
                    "success": False,
                    "deleted_items": deleted_pods,
                    "message": f"Failed to delete pod {pod_name} in {pod_namespace}: {str(e)[:100]}...",
                }

        return {
            "success": True,
            "deleted_items": deleted_pods,
            "message": f"Cleaned up {len(deleted_pods)} completed pods.",
        }
    except Exception as e:
        return {
            "success": False,
            "deleted_items": [],
            "message": f"Error cleaning up completed jobs: {str(e)[:100]}...",
        }


def ceph_object_store_present(
    name,
    namespace,
    replicas=1,
    port=80,
    ssl_enabled=False,
    annotations=None,
    gateway_instances=1,
    gateway_resources=None,
    enable_swift_api=True,
    swift_port=8080,
    swift_account_in_url=True,
    swift_url_prefix="swift",
    enable_s3_api=True,
    preserve_pools_on_delete=True,
    auth_keystone=False,
    keystone_url="",
    keystone_accepted_roles=None,
    keystone_implicit_tenants="swift",
    keystone_revocation_interval=1200,
    keystone_service_user_secret_name="",
    keystone_token_cache_size=1000,
    rgw_keystone_api_version="3",
    rgw_keystone_implicit_tenants="true",
    rgw_s3_auth_use_keystone="true",
    debug_rgw="0",
):
    """
    Ensure a Ceph Object Store (RGW - RADOS Gateway) exists in the specified Kubernetes namespace using Rook.

    Args:
        name (str): The name of the Ceph Object Store resource.
        namespace (str): The Kubernetes namespace for the Ceph Object Store (typically the Rook namespace).
        replicas (int, optional): Number of RGW replicas for high availability. Defaults to 1.
        port (int, optional): Port for the RGW service (S3 API). Defaults to 80.
        ssl_enabled (bool, optional): Enable SSL for RGW service. Defaults to False.
        annotations (dict, optional): Additional annotations for the Ceph Object Store resource. Defaults to None.
        gateway_instances (int, optional): Number of gateway instances. Defaults to 1.
        gateway_resources (dict, optional): Resource limits and requests for gateway pods. Defaults to None.
        enable_swift_api (bool, optional): Enable Swift API compatibility for the object store. Defaults to True.
        swift_port (int, optional): Port for Swift API if enabled. Defaults to 8080.
        swift_account_in_url (bool, optional): Include account in Swift URL structure. Defaults to True.
        swift_url_prefix (str, optional): URL prefix for Swift API. Defaults to "swift".
        enable_s3_api (bool, optional): Enable S3 API compatibility (default in RGW). Defaults to True.
        preserve_pools_on_delete (bool, optional): Preserve metadata and data pools when deleting the object store. Defaults to True.
        auth_keystone (bool, optional): Enable Keystone authentication integration. Defaults to False.
        keystone_url (str, optional): URL for Keystone authentication service. Defaults to "".
        keystone_accepted_roles (list, optional): List of roles accepted by Keystone for access. Defaults to None.
        keystone_implicit_tenants (str, optional): Implicit tenant handling for Keystone (e.g., "swift"). Defaults to "swift".
        keystone_revocation_interval (int, optional): Token revocation check interval in seconds. Defaults to 1200.
        keystone_service_user_secret_name (str): Name of the secret containing Keystone service user credentials. Mandatory if auth_keystone is True.
        keystone_token_cache_size (int, optional): Size of token cache for Keystone authentication. Defaults to 1000.
        rgw_keystone_api_version (str, optional): Keystone API version for RGW authentication. Defaults to "3".
        rgw_keystone_implicit_tenants (str, optional): Enable implicit tenants for Keystone-Swift integration. Defaults to "true".
        rgw_s3_auth_use_keystone (str, optional): Use Keystone for S3 authentication. Defaults to "true".
        debug_rgw (str, optional): Debug level for RGW (e.g., "15" for detailed logging). Defaults to "0" (no debugging).

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'message' (str), and 'resource' (dict, if created/updated).
    """
    try:
        _load_k8s_config()
        custom_api = client.CustomObjectsApi()

        # Define the CephObjectStore resource for Rook
        object_store_body = {
            "apiVersion": "ceph.rook.io/v1",
            "kind": "CephObjectStore",
            "metadata": {
                "name": name,
                "namespace": namespace,
            },
            "spec": {
                "metadataPool": {
                    "failureDomain": "host",
                    "replicated": {"size": replicas},
                },
                "dataPool": {
                    "failureDomain": "host",
                    "replicated": {"size": replicas},
                },
                "preservePoolsOnDelete": preserve_pools_on_delete,
                "gateway": {
                    "port": port,
                    "instances": gateway_instances,
                    "ssl": ssl_enabled,
                    "type": "s3",  # Primary API type for S3 compatibility
                },
                "protocols": {
                    "s3": {"enabled": enable_s3_api},
                    "swift": {
                        "enabled": enable_swift_api,
                        "accountInUrl": swift_account_in_url,
                        "urlPrefix": swift_url_prefix,
                    },
                },
            },
        }

        # Add annotations if provided
        if annotations:
            object_store_body["metadata"]["annotations"] = annotations

        # Add gateway resources if provided
        if gateway_resources:
            object_store_body["spec"]["gateway"]["resources"] = gateway_resources

        # Configure Keystone authentication if enabled, under auth.keystone and gateway rgwConfig
        if auth_keystone:
            if not keystone_service_user_secret_name:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"keystone_service_user_secret_name is mandatory when auth_keystone is enabled for {name} in namespace {namespace}.",
                    "resource": {},
                }
            object_store_body["spec"]["auth"] = {
                "keystone": {
                    "url": keystone_url,
                    "acceptedRoles": keystone_accepted_roles
                    if keystone_accepted_roles
                    else ["admin", "member", "service"],
                    "implicitTenants": keystone_implicit_tenants,
                    "revocationInterval": keystone_revocation_interval,
                    "serviceUserSecretName": keystone_service_user_secret_name,
                    "tokenCacheSize": keystone_token_cache_size,
                }
            }
            object_store_body["spec"]["gateway"]["rgwConfig"] = {
                "rgw_keystone_api_version": rgw_keystone_api_version,
                "rgw_keystone_implicit_tenants": rgw_keystone_implicit_tenants,
                "rgw_s3_auth_use_keystone": rgw_s3_auth_use_keystone,
                "debug_rgw": debug_rgw if debug_rgw != "0" else "0",
            }

        # Check if CephObjectStore already exists
        try:
            existing_store = custom_api.get_namespaced_custom_object(
                group="ceph.rook.io",
                version="v1",
                namespace=namespace,
                plural="cephobjectstores",
                name=name,
            )
            # Compare existing spec with desired spec (simplified check)
            if existing_store.get("spec") == object_store_body.get("spec"):
                return {
                    "success": True,
                    "updated": False,
                    "message": f"CephObjectStore {name} already exists in namespace {namespace} with matching spec.",
                    "resource": existing_store,
                }
            else:
                # Delete the existing CephObjectStore before recreating due to update limitations
                try:
                    custom_api.delete_namespaced_custom_object(
                        group="ceph.rook.io",
                        version="v1",
                        namespace=namespace,
                        plural="cephobjectstores",
                        name=name,
                    )
                    return {
                        "success": True,
                        "updated": True,
                        "message": f"CephObjectStore {name} deleted in namespace {namespace}, will recreate with new spec.",
                        "resource": {},
                    }
                except ApiException as delete_err:
                    return {
                        "success": False,
                        "updated": False,
                        "message": f"Failed to delete existing CephObjectStore {name} in namespace {namespace}: {str(delete_err)[:100]}...",
                        "resource": {},
                    }
        except ApiException as e:
            if e.status == 404:
                # CephObjectStore does not exist, create it
                created_store = custom_api.create_namespaced_custom_object(
                    group="ceph.rook.io",
                    version="v1",
                    namespace=namespace,
                    plural="cephobjectstores",
                    body=object_store_body,
                )
                # Wait briefly to ensure deletion has propagated if this is a recreation
                import time

                time.sleep(2)
                created_store = custom_api.create_namespaced_custom_object(
                    group="ceph.rook.io",
                    version="v1",
                    namespace=namespace,
                    plural="cephobjectstores",
                    body=object_store_body,
                )
                return {
                    "success": True,
                    "updated": True,
                    "message": f"CephObjectStore {name} created in namespace {namespace}.",
                    "resource": created_store,
                }
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to manage CephObjectStore {name} in namespace {namespace}: {str(e)}...",
                    "resource": {},
                }
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Error managing CephObjectStore {name} in namespace {namespace}: {str(e)[:100]}...",
            "resource": {},
        }

def kubernetes_deployment_present(
    name,
    namespace,
    replicas=1,
    image="",
    containers=None,
    labels=None,
    annotations=None,
    resources=None,
    node_selector=None,
    tolerations=None,
    affinity=None,
    service_account_name="",
    init_containers=None,
    volumes=None,
    restart_policy="Always",
):
    """
    Ensure a Kubernetes Deployment exists in the specified namespace.

    Args:
        name (str): The name of the Deployment.
        namespace (str): The Kubernetes namespace for the Deployment.
        replicas (int, optional): Number of replicas for the Deployment. Defaults to 1.
        image (str, optional): Container image to use if containers list is not provided. Defaults to "".
        containers (list, optional): List of container specifications. If not provided, a single container with the provided image is created. Defaults to None.
        labels (dict, optional): Labels to apply to the Deployment and Pod selector. Defaults to None.
        annotations (dict, optional): Annotations to apply to the Deployment. Defaults to None.
        resources (dict, optional): Resource limits and requests for containers. Defaults to None.
        node_selector (dict, optional): Node selector for scheduling the Pods. Defaults to None.
        tolerations (list, optional): Tolerations for scheduling the Pods on tainted nodes. Defaults to None.
        affinity (dict, optional): Affinity rules for scheduling the Pods. Defaults to None.
        service_account_name (str, optional): Service account name to assign to the Pods. Defaults to "".
        init_containers (list, optional): List of init container specifications. Defaults to None.
        volumes (list, optional): List of volume specifications for the Pods. Defaults to None.
        restart_policy (str, optional): Restart policy for the Pods. Defaults to "Always".

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'message' (str), and 'resource' (dict, if created/updated).
    """
    try:
        _load_k8s_config()
        apps_api = client.AppsV1Api()

        # Define container spec if containers list is not provided and image is specified
        if not containers and image:
            container = {
                "name": name,
                "image": image,
            }
            if resources:
                container["resources"] = resources
            containers = [container]

        # Define the Deployment spec
        deployment_body = {
            "apiVersion": "apps/v1",
            "kind": "Deployment",
            "metadata": {
                "name": name,
                "namespace": namespace,
            },
            "spec": {
                "replicas": replicas,
                "selector": {"matchLabels": labels if labels else {"app": name}},
                "template": {
                    "metadata": {"labels": labels if labels else {"app": name}},
                    "spec": {
                        "containers": containers if containers else [],
                        "restartPolicy": restart_policy,
                    },
                },
            },
        }

        # Add annotations if provided
        if annotations:
            deployment_body["metadata"]["annotations"] = annotations

        # Add optional pod spec fields
        pod_spec = deployment_body["spec"]["template"]["spec"]
        if node_selector:
            pod_spec["nodeSelector"] = node_selector
        if tolerations:
            pod_spec["tolerations"] = tolerations
        if affinity:
            pod_spec["affinity"] = affinity
        if service_account_name:
            pod_spec["serviceAccountName"] = service_account_name
        if init_containers:
            pod_spec["initContainers"] = init_containers
        if volumes:
            pod_spec["volumes"] = volumes

        # Check if Deployment already exists
        try:
            existing_deployment = apps_api.read_namespaced_deployment(
                name=name, namespace=namespace
            )
            # Compare existing spec with desired spec (simplified check)
            if existing_deployment.spec.to_dict() == deployment_body["spec"]:
                return {
                    "success": True,
                    "updated": False,
                    "message": f"Deployment {name} already exists in namespace {namespace} with matching spec.",
                    "resource": existing_deployment.to_dict(),
                }
            else:
                # Update the existing Deployment
                updated_deployment = apps_api.replace_namespaced_deployment(
                    name=name, namespace=namespace, body=deployment_body
                )
                return {
                    "success": True,
                    "updated": True,
                    "message": f"Deployment {name} updated in namespace {namespace}.",
                    "resource": updated_deployment.to_dict(),
                }
        except ApiException as e:
            if e.status == 404:
                # Deployment does not exist, create it
                created_deployment = apps_api.create_namespaced_deployment(
                    namespace=namespace, body=deployment_body
                )
                return {
                    "success": True,
                    "updated": True,
                    "message": f"Deployment {name} created in namespace {namespace}.",
                    "resource": created_deployment.to_dict(),
                }
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to manage Deployment {name} in namespace {namespace}: {str(e)[:100]}...",
                    "resource": {},
                }
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Error managing Deployment {name} in namespace {namespace}: {str(e)[:100]}...",
            "resource": {},
        }


def job_present(
    namespace,
    name,
    image,
    command=None,
    args=None,
    service_account=None,
    restart_policy="OnFailure",
    backoff_limit=1,
    ttl_seconds_after_finished=300,
    labels=None,
    annotations=None,
    env=None,
    volumes=None,
    volume_mounts=None,
    resources=None,
    spec=None,
):
    """
    Ensure a Kubernetes Job exists.

    Args:
        namespace (str): Namespace for the Job.
        name (str): Name of the Job.
        image (str): Container image.
        command (list, optional): Entrypoint command.
        args (list, optional): Arguments to the command.
        service_account (str, optional): ServiceAccount to run as.
        restart_policy (str): "OnFailure" or "Never".
        backoff_limit (int): Number of retries before marking as failed.
        ttl_seconds_after_finished (int): Time to keep the Job after it finishes.
        labels (dict, optional): Labels for the Job.
        annotations (dict, optional): Annotations for the Job.
        env (list, optional): Environment variables.
        volumes (list, optional): Volume definitions.
        volume_mounts (list, optional): Volume mounts for containers.
        resources (dict, optional): Resource requests/limits.
        spec (dict, optional): Full Job spec (overrides other arguments).

    Returns:
        dict: success, updated, message
    """
    try:
        _load_k8s_config()
        batch_api = client.BatchV1Api()

        if spec is None:
            container = {"name": name, "image": image}
            if command:
                container["command"] = command
            if args:
                container["args"] = args
            if env:
                container["env"] = env
            if volume_mounts:
                container["volumeMounts"] = volume_mounts
            if resources:
                container["resources"] = resources

            pod_spec = {
                "restartPolicy": restart_policy,
                "containers": [container],
            }
            if service_account:
                pod_spec["serviceAccountName"] = service_account
            if volumes:
                pod_spec["volumes"] = volumes

            job_spec = {
                "template": {"spec": pod_spec},
                "backoffLimit": backoff_limit,
            }
            if ttl_seconds_after_finished is not None:
                job_spec["ttlSecondsAfterFinished"] = ttl_seconds_after_finished

            job_body = {
                "apiVersion": "batch/v1",
                "kind": "Job",
                "metadata": {"name": name, "namespace": namespace},
                "spec": job_spec,
            }
            if labels:
                job_body["metadata"]["labels"] = labels
            if annotations:
                job_body["metadata"]["annotations"] = annotations
        else:
            job_body = {
                "apiVersion": "batch/v1",
                "kind": "Job",
                "metadata": {"name": name, "namespace": namespace},
                "spec": spec,
            }

        try:
            existing = batch_api.read_namespaced_job(name=name, namespace=namespace)
            existing_annotations = (existing.metadata.annotations or {}) if existing.metadata else {}
            desired_annotations = job_body["metadata"].get("annotations", {})
            if existing.spec == job_body["spec"] and existing_annotations == desired_annotations:
                return {
                    "success": True,
                    "updated": False,
                    "message": f"Job {name} already exists and matches desired state",
                }
            # Most Job spec fields (pod template, selector, etc.) are immutable
            # after creation, so an in-place replace will fail with a 422 for
            # any real change. Delete and recreate instead.
            batch_api.delete_namespaced_job(
                name=name,
                namespace=namespace,
                propagation_policy="Foreground",
            )
            _wait_for_job_deleted(batch_api, name, namespace)
            batch_api.create_namespaced_job(namespace=namespace, body=job_body)
            return {"success": True, "updated": True, "message": f"Job {name} recreated"}
        except ApiException as e:
            if e.status == 404:
                batch_api.create_namespaced_job(namespace=namespace, body=job_body)
                return {"success": True, "updated": True, "message": f"Job {name} created"}
            return {"success": False, "updated": False, "message": str(e)}
    except Exception as e:
        return {"success": False, "updated": False, "message": str(e)}


def _wait_for_job_deleted(batch_api, name, namespace, timeout=30):
    import time as _time

    deadline = _time.time() + timeout
    while _time.time() < deadline:
        try:
            batch_api.read_namespaced_job(name=name, namespace=namespace)
        except ApiException as e:
            if e.status == 404:
                return
            raise
        _time.sleep(1)


def networkattachmentdefinition_present(
    name,
    namespace="default",
    cni_type="macvlan",
    master="eth0",
    mode="bridge",
    cidr=None,
    range_start=None,
    range_end=None,
    gateway=None,
    ipam_type="whereabouts",
):
    """
    Ensure a Multus NetworkAttachmentDefinition exists with the specified IPAM configuration.

    This creates a NetworkAttachmentDefinition CRD for use with Multus CNI.

    Args:
        name (str): Name of the NetworkAttachmentDefinition (e.g. 'sfe', 'sbe')
        namespace (str): Kubernetes namespace. Defaults to 'default'.
        cni_type (str): CNI plugin type. Defaults to 'macvlan'.
        master (str): Master interface for macvlan. Defaults to 'eth0'.
        mode (str): Macvlan mode. Defaults to 'bridge'.
        cidr (str): IPAM CIDR range (e.g. '10.150.2.0/24')
        range_start (str): Starting IP in the range
        range_end (str): Ending IP in the range
        gateway (str, optional): Gateway IP. If None, no gateway is configured.
        ipam_type (str): IPAM plugin to use. Defaults to 'whereabouts'.

    Returns:
        dict: Dictionary with success, updated, message, and resource info.
    """
    try:
        _load_k8s_config()
        custom_api = client.CustomObjectsApi()

        group = "k8s.cni.cncf.io"
        version = "v1"
        plural = "network-attachment-definitions"

        # Build the IPAM configuration
        ipam_config = {
            "type": ipam_type,
            "range": cidr,
        }
        if range_start:
            ipam_config["range_start"] = range_start
        if range_end:
            ipam_config["range_end"] = range_end
        if gateway:
            ipam_config["gateway"] = gateway

        # Build the CNI config
        config = {
            "cniVersion": "0.3.1",
            "name": name,
            "type": cni_type,
            "master": master,
            "mode": mode,
            "ipam": ipam_config,
        }

        nad_body = {
            "apiVersion": f"{group}/{version}",
            "kind": "NetworkAttachmentDefinition",
            "metadata": {
                "name": name,
                "namespace": namespace,
            },
            "spec": {"config": json.dumps(config)},
        }

        # Check if it already exists
        exists = False
        try:
            existing = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=name,
            )
            exists = True
            # Simple check - if config differs significantly, we'll update
            current_config = json.loads(existing.get("spec", {}).get("config", "{}"))
            if current_config.get("ipam", {}).get("range") != cidr:
                matches = False
            else:
                matches = True
        except ApiException as e:
            if e.status == 404:
                exists = False
                matches = False
            else:
                raise

        if not exists or not matches:
            if exists:
                custom_api.replace_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    name=name,
                    body=nad_body,
                )
                return {
                    "success": True,
                    "updated": True,
                    "message": f"NetworkAttachmentDefinition {name} updated in {namespace}",
                }
            else:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=nad_body,
                )
                return {
                    "success": True,
                    "updated": True,
                    "message": f"NetworkAttachmentDefinition {name} created in {namespace}",
                }
        else:
            return {
                "success": True,
                "updated": False,
                "message": f"NetworkAttachmentDefinition {name} already exists and matches desired state in {namespace}",
            }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure NetworkAttachmentDefinition {name}: {str(e)[:100]}...",
        }


def gateway_present(
    namespace,
    name,
    gateway_class_name,
    listeners=None,
    addresses=None,
    allowed_listeners=None,
    spec=None,
):
    """
    Ensure a Kubernetes Gateway (Gateway API) exists.

    Special behavior:
    - If `allowed_listeners` is provided **and** no `listeners` are given, listeners on
      ports 80 (HTTP) and 443 (HTTPS) are automatically added.
      This satisfies Gateway API validation while still using allowedListeners for
      cross-namespace routing (parent/reference gateway pattern).
    - You can still override this by passing a full `spec` dict or explicit listeners.

    Args:
        namespace (str): Namespace for the Gateway resource.
        name (str): Name of the Gateway.
        gateway_class_name (str): The GatewayClass this Gateway references.
        listeners (list, optional): List of listener definitions.
        addresses (list, optional): List of address definitions.
        allowed_listeners (dict, optional): allowedListeners block for cross-namespace routing.
            Example: {"namespaces": {"from": "Same"}}
        spec (dict, optional): Full spec dictionary (overrides all other parameters).

    Returns:
        dict: A dictionary with 'success', 'updated', and 'message'.

    CLI Example:
        salt '*' kinetic_k8s.gateway_present default internal-gateway my-gateway-class \
            allowed_listeners='{"namespaces": {"from": "Same"}}'
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "gateway.networking.k8s.io"
        version = "v1"
        plural = "gateways"
        kind = "Gateway"

        # Build spec if not provided directly
        if spec is None:
            spec = {"gatewayClassName": gateway_class_name}

            if listeners:
                spec["listeners"] = listeners
            elif allowed_listeners:
                # When only allowedListeners is used (common for parent/reference gateways),
                # we must still provide listeners. Many controllers require at least one.
                # We use the standard ports 80 and 443 as requested.
                spec["listeners"] = [
                    {
                        "name": "http",
                        "port": 80,
                        "protocol": "HTTP",
                        "allowedRoutes": {
                            "namespaces": {"from": "Same"}
                        }
                    },
                    {
                        "name": "https",
                        "port": 443,
                        "protocol": "HTTPS",
                        "allowedRoutes": {
                            "namespaces": {"from": "Same"}
                        }
                    }
                ]

            if addresses:
                spec["addresses"] = addresses
            if allowed_listeners:
                spec["allowedListeners"] = allowed_listeners
        else:
            # User provided full spec - respect it, but merge allowed_listeners if given
            spec = dict(spec)
            if "gatewayClassName" not in spec:
                spec["gatewayClassName"] = gateway_class_name
            if allowed_listeners and "allowedListeners" not in spec:
                spec["allowedListeners"] = allowed_listeners

        body = {
            "apiVersion": f"{group}/{version}",
            "kind": kind,
            "metadata": {"name": name, "namespace": namespace},
            "spec": spec,
        }

        exists = False
        updated = False
        matches = False
        resource = None

        # Check if Gateway exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=name,
            )
            exists = True
            current_spec = resource.get("spec", {})
            if current_spec == spec:
                matches = True
                message = f"Gateway {name} in namespace {namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"Gateway {name} in namespace {namespace} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"Gateway {name} in namespace {namespace} does not exist"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking Gateway {name}: {str(e)[:80]}...",
                }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=body,
                )
                updated = True
                message = f"Gateway {name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create Gateway {name}: {str(e)}...",
                }
        elif not matches:
            try:
                # Include resourceVersion to avoid conflicts
                if (
                    resource
                    and "metadata" in resource
                    and "resourceVersion" in resource["metadata"]
                ):
                    body["metadata"]["resourceVersion"] = resource["metadata"]["resourceVersion"]
                custom_api.replace_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    name=name,
                    body=body,
                )
                updated = True
                message = f"Gateway {name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update Gateway {name}: {str(e)}...",
                }
        else:
            message = f"Gateway {name} in namespace {namespace} already exists and matches desired state"

        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure Gateway {name}: {str(e)}",
        }


def httproute_present(
    namespace,
    name,
    parent_refs=None,
    rules=None,
    hostname=None,
    hostnames=None,
    spec=None,
):
    """
    Ensure a Kubernetes HTTPRoute (Gateway API) exists in the specified namespace.

    Args:
        namespace (str): Namespace for the HTTPRoute.
        name (str): Name of the HTTPRoute.
        parent_refs (list, optional): List of parentRefs (which Gateways this route attaches to).
        rules (list, optional): List of HTTPRoute rules (matches, backendRefs, filters).
        hostname (str, optional): Single hostname for the route (will be converted to hostnames list).
        hostnames (list, optional): List of hostnames for the route.
        spec (dict, optional): Full spec if provided (hostnames will be merged if provided).

    Returns:
        dict: A dictionary with 'success', 'updated', and 'message'.

    CLI Example:
        salt '*' kinetic_k8s.httproute_present default my-route \
            parent_refs='[{"name": "my-gateway", "sectionName": "http"}]' \
            rules='[{"matches": [{"path": {"type": "PathPrefix", "value": "/"}}], "backendRefs": [{"name": "my-service", "port": 80}]}]' \
            hostname=docs.int.rsc.gacyberrange.org

        # or with full spec and hostnames list
        salt '*' kinetic_k8s.httproute_present default my-route \
            spec='{"parentRefs": [...], "rules": [...]}' \
            hostnames='["docs.int.rsc.gacyberrange.org", "docs2.int.rsc.gacyberrange.org"]'
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "gateway.networking.k8s.io"
        version = "v1"
        plural = "httproutes"
        kind = "HTTPRoute"

        # Build spec if not provided directly
        if spec is None:
            spec = {}
            if parent_refs:
                spec["parentRefs"] = parent_refs
            if rules:
                spec["rules"] = rules
        else:
            spec = dict(spec)  # copy

        # Merge hostnames into spec if provided
        if hostname or hostnames:
            hn = hostnames or ([hostname] if hostname else [])
            if hn:
                spec["hostnames"] = hn

        body = {
            "apiVersion": f"{group}/{version}",
            "kind": kind,
            "metadata": {"name": name, "namespace": namespace},
            "spec": spec,
        }

        exists = False
        updated = False
        matches = False
        resource = None

        # Check if HTTPRoute exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=name,
            )
            exists = True
            current_spec = resource.get("spec", {})
            if current_spec == spec:
                matches = True
                message = f"HTTPRoute {name} in namespace {namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"HTTPRoute {name} in namespace {namespace} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"HTTPRoute {name} in namespace {namespace} does not exist"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking HTTPRoute {name}: {str(e)[:50]}...",
                }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=body,
                )
                updated = True
                message = f"HTTPRoute {name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create HTTPRoute {name}: {str(e)[:100]}...",
                }
        elif not matches:
            try:
                if (
                    resource
                    and "metadata" in resource
                    and "resourceVersion" in resource["metadata"]
                ):
                    body["metadata"]["resourceVersion"] = resource["metadata"]["resourceVersion"]
                custom_api.replace_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    name=name,
                    body=body,
                )
                updated = True
                message = f"HTTPRoute {name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update HTTPRoute {name}: {str(e)[:100]}...",
                }
        else:
            message = f"HTTPRoute {name} in namespace {namespace} already exists and matches desired state"

        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"HTTPRoute operation error: {str(e)[:100]}...",
        }


def _normalize_local_policy_ref(ref, default_kind):
    """
    Normalize a LocalPolicyTargetReference-style dict (used by targetRefs and
    caCertificateRefs on BackendTLSPolicy) so that the required `group` and
    `kind` fields are always present, even if the caller omitted them.

    The Gateway API CRD schema marks `group` as a required field on these
    reference objects (with an empty string meaning "core API group"), so
    omitting it entirely causes a 422 Unprocessable Entity from the API
    server, not just a validation default.
    """
    ref = dict(ref)
    ref.setdefault("group", "")
    ref.setdefault("kind", default_kind)
    return ref


def backendtlspolicy_present(
    namespace,
    name,
    target_refs=None,
    hostname=None,
    ca_certificate_refs=None,
    well_known_ca_certificates=None,
    validation=None,
    spec=None,
    version="v1",
):
    """
    Ensure a Kubernetes BackendTLSPolicy (Gateway API) exists in the specified namespace.

    BackendTLSPolicy configures TLS from the Gateway/proxy to a backend Service
    (verifying the backend's certificate), similar in purpose to the
    'backend protocol: HTTPS' style annotations used with Ingress.

    Args:
        namespace (str): Namespace for the BackendTLSPolicy.
        name (str): Name of the BackendTLSPolicy.
        target_refs (list, optional): List of targetRefs (which Services this
            policy applies to). Each entry supports: group (default ""),
            kind (default "Service"), name, sectionName (optional, matches a
            named port on the Service).
        hostname (str, optional): SNI hostname used to validate the backend's
            certificate. Merged into validation.hostname unless validation
            already sets it.
        ca_certificate_refs (list, optional): List of refs to CA certificate
            ConfigMaps/Secrets used to validate the backend certificate.
            Each entry supports: group (default ""), kind (default
            "ConfigMap"), name. Merged into validation.caCertificateRefs
            unless validation already sets it.
        well_known_ca_certificates (str, optional): Set to "System" to trust
            the system CA bundle instead of caCertificateRefs. Merged into
            validation.wellKnownCACertificates unless validation already
            sets it.
        validation (dict, optional): Full validation dict. Built-from-kwargs
            values (hostname, ca_certificate_refs, well_known_ca_certificates)
            are merged in for any keys not already present.
        spec (dict, optional): Full spec dict; overrides target_refs/
            validation/hostname/ca_certificate_refs/well_known_ca_certificates
            entirely if provided.
        version (str): Gateway API version for this CRD (default: v1, the
            stable/GA version as of Gateway API 1.3+; use v1alpha3 or
            v1alpha2 for older Gateway API installations where
            BackendTLSPolicy is still experimental).

    Returns:
        dict: A dictionary with 'success', 'updated', and 'message'.

    CLI Example:
        salt '*' kinetic_k8s.backendtlspolicy_present efk opensearch-backend-tls \
            target_refs='[{"kind": "Service", "name": "opensearch-cluster-master", "sectionName": "9200"}]' \
            hostname=opensearch-cluster-master.efk.svc.cluster.local \
            well_known_ca_certificates=System
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "gateway.networking.k8s.io"
        plural = "backendtlspolicies"
        kind = "BackendTLSPolicy"

        # Build spec if not provided directly
        if spec is None:
            spec = {}
            if target_refs:
                spec["targetRefs"] = [
                    _normalize_local_policy_ref(ref, "Service") for ref in target_refs
                ]

            built_validation = dict(validation) if validation else {}
            if hostname and "hostname" not in built_validation:
                built_validation["hostname"] = hostname
            if ca_certificate_refs and "caCertificateRefs" not in built_validation:
                built_validation["caCertificateRefs"] = [
                    _normalize_local_policy_ref(ref, "ConfigMap")
                    for ref in ca_certificate_refs
                ]
            if well_known_ca_certificates and "wellKnownCACertificates" not in built_validation:
                built_validation["wellKnownCACertificates"] = well_known_ca_certificates
            if built_validation:
                spec["validation"] = built_validation
        else:
            spec = dict(spec)  # copy

        body = {
            "apiVersion": f"{group}/{version}",
            "kind": kind,
            "metadata": {"name": name, "namespace": namespace},
            "spec": spec,
        }

        exists = False
        updated = False
        matches = False
        resource = None

        # Check if BackendTLSPolicy exists
        try:
            resource = custom_api.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=name,
            )
            exists = True
            current_spec = resource.get("spec", {})
            if current_spec == spec:
                matches = True
                message = f"BackendTLSPolicy {name} in namespace {namespace} already exists and matches desired spec"
            else:
                matches = False
                message = f"BackendTLSPolicy {name} in namespace {namespace} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"BackendTLSPolicy {name} in namespace {namespace} does not exist"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking BackendTLSPolicy {name}: {str(e)[:80]}...",
                }

        if not exists:
            try:
                custom_api.create_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    body=body,
                )
                updated = True
                message = f"BackendTLSPolicy {name} created in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create BackendTLSPolicy {name}: {str(e)[:100]}...",
                }
        elif not matches:
            try:
                if (
                    resource
                    and "metadata" in resource
                    and "resourceVersion" in resource["metadata"]
                ):
                    body["metadata"]["resourceVersion"] = resource["metadata"]["resourceVersion"]
                custom_api.replace_namespaced_custom_object(
                    group=group,
                    version=version,
                    namespace=namespace,
                    plural=plural,
                    name=name,
                    body=body,
                )
                updated = True
                message = f"BackendTLSPolicy {name} updated in namespace {namespace}"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update BackendTLSPolicy {name}: {str(e)[:100]}...",
                }
        else:
            message = f"BackendTLSPolicy {name} in namespace {namespace} already exists and matches desired state"

        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"BackendTLSPolicy operation error: {str(e)[:100]}...",
        }


def gatewayclass_present(
    name,
    spec=None,
):
    """
    Ensure a cluster-scoped GatewayClass (Gateway API) exists.

    Args:
        name (str): Name of the GatewayClass.
        spec (dict): Specification for the GatewayClass (e.g. controllerName).

    Returns:
        dict: success, updated, message.
    """
    try:
        _load_k8s_config()

        custom_api = client.CustomObjectsApi()
        group = "gateway.networking.k8s.io"
        version = "v1"
        plural = "gatewayclasses"
        kind = "GatewayClass"

        if spec is None:
            spec = {"controllerName": "gateway.kgateway.dev/kgateway"}  # sensible default

        body = {
            "apiVersion": f"{group}/{version}",
            "kind": kind,
            "metadata": {"name": name},
            "spec": spec,
        }

        exists = False
        updated = False
        matches = False
        resource = None

        try:
            resource = custom_api.get_cluster_custom_object(
                group=group, version=version, plural=plural, name=name
            )
            exists = True
            current_spec = resource.get("spec", {})
            if current_spec == spec:
                matches = True
                message = f"GatewayClass {name} already exists and matches desired spec"
            else:
                matches = False
                message = f"GatewayClass {name} exists but spec differs"
        except ApiException as e:
            if e.status == 404:
                exists = False
                message = f"GatewayClass {name} does not exist"
            else:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking GatewayClass {name}: {str(e)[:50]}...",
                }

        if not exists:
            try:
                custom_api.create_cluster_custom_object(
                    group=group, version=version, plural=plural, body=body
                )
                updated = True
                message = f"GatewayClass {name} created"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to create GatewayClass {name}: {str(e)[:100]}...",
                }
        elif not matches:
            try:
                if (
                    resource
                    and "metadata" in resource
                    and "resourceVersion" in resource["metadata"]
                ):
                    body["metadata"]["resourceVersion"] = resource["metadata"]["resourceVersion"]
                custom_api.replace_cluster_custom_object(
                    group=group,
                    version=version,
                    plural=plural,
                    name=name,
                    body=body,
                )
                updated = True
                message = f"GatewayClass {name} updated"
            except ApiException as e:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Failed to update GatewayClass {name}: {str(e)[:100]}...",
                }
        else:
            message = f"GatewayClass {name} already exists and matches desired state"

        return {"success": True, "updated": updated, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"GatewayClass operation error: {str(e)[:100]}...",
        }


def serviceaccount_present(namespace, name, labels=None, annotations=None):
    """
    Ensure a Kubernetes ServiceAccount exists in the specified namespace.

    Args:
        namespace (str): The namespace for the ServiceAccount.
        name (str): The name of the ServiceAccount.
        labels (dict, optional): Labels to apply. Defaults to None.
        annotations (dict, optional): Annotations to apply. Defaults to None.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic_k8s.serviceaccount_present rook-ceph rook-vault-auth
    """
    try:
        _load_k8s_config()

        core_v1_api = client.CoreV1Api()

        # Check if ServiceAccount exists
        try:
            core_v1_api.read_namespaced_service_account(name=name, namespace=namespace)
            return {
                "success": True,
                "updated": False,
                "message": f"ServiceAccount {name} already exists in namespace {namespace}",
            }
        except ApiException as e:
            if e.status != 404:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking ServiceAccount {name}: {str(e)[:100]}...",
                }

        # Create the ServiceAccount
        sa_body = client.V1ServiceAccount(
            metadata=client.V1ObjectMeta(
                name=name,
                namespace=namespace,
                labels=labels or {},
                annotations=annotations or {},
            )
        )
        core_v1_api.create_namespaced_service_account(namespace=namespace, body=sa_body)
        return {
            "success": True,
            "updated": True,
            "message": f"ServiceAccount {name} created in namespace {namespace}",
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"ServiceAccount operation error: {str(e)[:100]}...",
        }


def clusterrolebinding_present(name, cluster_role, service_accounts):
    """
    Ensure a Kubernetes ClusterRoleBinding exists binding a ClusterRole to ServiceAccounts.

    Args:
        name (str): The name of the ClusterRoleBinding.
        cluster_role (str): The name of the ClusterRole to bind (e.g. 'system:auth-delegator').
        service_accounts (list): List of "namespace:serviceaccount" strings
            (e.g. ["rook-ceph:rook-vault-auth"]).

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic_k8s.clusterrolebinding_present vault-tokenreview-binding \
            system:auth-delegator '["rook-ceph:rook-vault-auth"]'
    """
    try:
        _load_k8s_config()

        rbac_api = client.RbacAuthorizationV1Api()

        # Build desired subjects
        subjects = []
        for sa in service_accounts:
            sa_namespace, sa_name = sa.split(":", 1)
            subjects.append(
                client.RbacV1Subject(
                    kind="ServiceAccount",
                    name=sa_name,
                    namespace=sa_namespace,
                )
            )

        # Check if ClusterRoleBinding exists
        exists = False
        matches = False
        try:
            existing = rbac_api.read_cluster_role_binding(name=name)
            exists = True
            current_role = existing.role_ref.name if existing.role_ref else ""
            current_subjects = {
                (s.kind, s.namespace, s.name) for s in (existing.subjects or [])
            }
            desired_subjects = {("ServiceAccount", s.namespace, s.name) for s in subjects}
            if current_role == cluster_role and current_subjects == desired_subjects:
                matches = True
        except ApiException as e:
            if e.status != 404:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking ClusterRoleBinding {name}: {str(e)[:100]}...",
                }

        if exists and matches:
            return {
                "success": True,
                "updated": False,
                "message": f"ClusterRoleBinding {name} already exists and matches desired state",
            }

        crb_body = client.V1ClusterRoleBinding(
            metadata=client.V1ObjectMeta(name=name),
            role_ref=client.V1RoleRef(
                api_group="rbac.authorization.k8s.io",
                kind="ClusterRole",
                name=cluster_role,
            ),
            subjects=subjects,
        )

        if not exists:
            rbac_api.create_cluster_role_binding(body=crb_body)
            message = f"ClusterRoleBinding {name} created"
        else:
            rbac_api.replace_cluster_role_binding(name=name, body=crb_body)
            message = f"ClusterRoleBinding {name} updated"

        return {"success": True, "updated": True, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"ClusterRoleBinding operation error: {str(e)[:100]}...",
        }


def _non_resource_urls_kwarg_name():
    """
    Determine which keyword the installed kubernetes client library's
    V1PolicyRule accepts for the non-resource-URLs field.

    This varies across kubernetes client versions due to a codegen quirk:
    some versions use the correctly-spelled non_resource_urls, others use
    non_resource_ur_ls. Our own rule dict API always uses the
    correctly-spelled non_resource_urls key regardless of which one the
    installed client actually accepts.
    """
    params = inspect.signature(client.V1PolicyRule.__init__).parameters
    if "non_resource_urls" in params:
        return "non_resource_urls"
    if "non_resource_ur_ls" in params:
        return "non_resource_ur_ls"
    return None


def _build_policy_rules(rules):
    """
    Build a list of kubernetes.client.V1PolicyRule from a list of rule dicts.

    Each rule dict supports the keys: api_groups, resources, verbs,
    resource_names, non_resource_urls (all optional except verbs, which is
    required by the Kubernetes API).
    """
    non_resource_urls_kwarg = _non_resource_urls_kwarg_name()
    policy_rules = []
    for rule in rules or []:
        kwargs = {
            "api_groups": rule.get("api_groups", [""]),
            "resources": rule.get("resources") or None,
            "verbs": rule.get("verbs", []),
            "resource_names": rule.get("resource_names") or None,
        }
        non_resource_urls = rule.get("non_resource_urls")
        if non_resource_urls and non_resource_urls_kwarg:
            kwargs[non_resource_urls_kwarg] = non_resource_urls
        policy_rules.append(client.V1PolicyRule(**kwargs))
    return policy_rules


def _normalize_rule(rule):
    """Build a hashable, order-independent representation of a V1PolicyRule."""
    non_resource_urls = getattr(rule, "non_resource_urls", None)
    if non_resource_urls is None:
        non_resource_urls = getattr(rule, "non_resource_ur_ls", None)
    return (
        tuple(sorted(rule.api_groups or [])),
        tuple(sorted(rule.resources or [])),
        tuple(sorted(rule.verbs or [])),
        tuple(sorted(rule.resource_names or [])),
        tuple(sorted(non_resource_urls or [])),
    )


def _rules_match(existing_rules, desired_rules):
    """Compare two lists of V1PolicyRule for equality, ignoring order."""
    existing_norm = sorted(_normalize_rule(r) for r in (existing_rules or []))
    desired_norm = sorted(_normalize_rule(r) for r in (desired_rules or []))
    return existing_norm == desired_norm


def _build_rbac_subjects(groups=None, users=None, service_accounts=None, subjects=None, default_namespace=None):
    """
    Build a list of kubernetes.client.RbacV1Subject from convenience kwargs.

    Args:
        groups (list): Group names (e.g. LDAP/OIDC group names surfaced in
            the "groups" claim of an OIDC ID token). Bound as kind=Group.
        users (list): Usernames. Bound as kind=User.
        service_accounts (list): "namespace:serviceaccount" strings, or bare
            "serviceaccount" names (defaulting to default_namespace).
            Bound as kind=ServiceAccount.
        subjects (list): Raw subject dicts for full control, e.g.
            [{"kind": "Group", "name": "my-group"}]. Merged with the
            convenience kwargs above.
        default_namespace (str): Namespace to use for bare ServiceAccount
            names that don't include a "namespace:" prefix.

    Returns:
        list: kubernetes.client.RbacV1Subject objects.
    """
    result = []
    for group_name in groups or []:
        result.append(
            client.RbacV1Subject(
                kind="Group",
                name=group_name,
                api_group="rbac.authorization.k8s.io",
            )
        )
    for username in users or []:
        result.append(
            client.RbacV1Subject(
                kind="User",
                name=username,
                api_group="rbac.authorization.k8s.io",
            )
        )
    for sa in service_accounts or []:
        if ":" in sa:
            sa_namespace, sa_name = sa.split(":", 1)
        else:
            sa_namespace, sa_name = default_namespace, sa
        result.append(
            client.RbacV1Subject(
                kind="ServiceAccount",
                name=sa_name,
                namespace=sa_namespace,
            )
        )
    for subject in subjects or []:
        kind = subject.get("kind", "Group")
        api_group = None if kind == "ServiceAccount" else "rbac.authorization.k8s.io"
        result.append(
            client.RbacV1Subject(
                kind=kind,
                name=subject["name"],
                namespace=subject.get("namespace", default_namespace if kind == "ServiceAccount" else None),
                api_group=subject.get("api_group", api_group),
            )
        )
    return result


def _subject_set(subjects):
    """Build a hashable, order-independent representation of RBAC subjects."""
    return {(s.kind, s.namespace or "", s.name) for s in (subjects or [])}


def role_present(namespace, name, rules):
    """
    Ensure a namespaced Kubernetes Role exists with the given rules.

    Args:
        namespace (str): Namespace for the Role.
        name (str): Name of the Role.
        rules (list): List of rule dicts, e.g.
            [{"api_groups": [""], "resources": ["pods"], "verbs": ["get", "list"]}]

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic_k8s.role_present default pod-reader \
            '[{"api_groups": [""], "resources": ["pods"], "verbs": ["get", "list"]}]'
    """
    try:
        _load_k8s_config()
        rbac_api = client.RbacAuthorizationV1Api()
        desired_rules = _build_policy_rules(rules)

        exists = False
        try:
            existing = rbac_api.read_namespaced_role(name=name, namespace=namespace)
            exists = True
        except ApiException as e:
            if e.status != 404:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking Role {name}: {str(e)[:100]}...",
                }
            existing = None

        if exists and _rules_match(existing.rules, desired_rules):
            return {
                "success": True,
                "updated": False,
                "message": f"Role {name} in namespace {namespace} already matches desired state",
            }

        role_body = client.V1Role(
            metadata=client.V1ObjectMeta(name=name, namespace=namespace),
            rules=desired_rules,
        )

        if not exists:
            rbac_api.create_namespaced_role(namespace=namespace, body=role_body)
            message = f"Role {name} created in namespace {namespace}"
        else:
            rbac_api.replace_namespaced_role(name=name, namespace=namespace, body=role_body)
            message = f"Role {name} updated in namespace {namespace}"

        return {"success": True, "updated": True, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Role operation error: {str(e)[:100]}...",
        }


def role_absent(namespace, name):
    """
    Ensure a namespaced Kubernetes Role does not exist.

    Args:
        namespace (str): Namespace of the Role.
        name (str): Name of the Role.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).
    """
    try:
        _load_k8s_config()
        rbac_api = client.RbacAuthorizationV1Api()
        try:
            rbac_api.delete_namespaced_role(name=name, namespace=namespace)
        except ApiException as e:
            if e.status == 404:
                return {
                    "success": True,
                    "updated": False,
                    "message": f"Role {name} in namespace {namespace} already absent",
                }
            return {
                "success": False,
                "updated": False,
                "message": f"Error deleting Role {name}: {str(e)[:100]}...",
            }

        return {
            "success": True,
            "updated": True,
            "message": f"Role {name} deleted from namespace {namespace}",
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Role delete error: {str(e)[:100]}...",
        }


def clusterrole_present(name, rules):
    """
    Ensure a Kubernetes ClusterRole exists with the given rules.

    Args:
        name (str): Name of the ClusterRole.
        rules (list): List of rule dicts, e.g.
            [{"api_groups": [""], "resources": ["pods"], "verbs": ["get", "list"]}]

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic_k8s.clusterrole_present pod-reader \
            '[{"api_groups": [""], "resources": ["pods"], "verbs": ["get", "list"]}]'
    """
    try:
        _load_k8s_config()
        rbac_api = client.RbacAuthorizationV1Api()
        desired_rules = _build_policy_rules(rules)

        exists = False
        try:
            existing = rbac_api.read_cluster_role(name=name)
            exists = True
        except ApiException as e:
            if e.status != 404:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking ClusterRole {name}: {str(e)[:100]}...",
                }
            existing = None

        if exists and _rules_match(existing.rules, desired_rules):
            return {
                "success": True,
                "updated": False,
                "message": f"ClusterRole {name} already matches desired state",
            }

        role_body = client.V1ClusterRole(
            metadata=client.V1ObjectMeta(name=name),
            rules=desired_rules,
        )

        if not exists:
            rbac_api.create_cluster_role(body=role_body)
            message = f"ClusterRole {name} created"
        else:
            rbac_api.replace_cluster_role(name=name, body=role_body)
            message = f"ClusterRole {name} updated"

        return {"success": True, "updated": True, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"ClusterRole operation error: {str(e)[:100]}...",
        }


def clusterrole_absent(name):
    """
    Ensure a Kubernetes ClusterRole does not exist.

    Args:
        name (str): Name of the ClusterRole.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).
    """
    try:
        _load_k8s_config()
        rbac_api = client.RbacAuthorizationV1Api()
        try:
            rbac_api.delete_cluster_role(name=name)
        except ApiException as e:
            if e.status == 404:
                return {
                    "success": True,
                    "updated": False,
                    "message": f"ClusterRole {name} already absent",
                }
            return {
                "success": False,
                "updated": False,
                "message": f"Error deleting ClusterRole {name}: {str(e)[:100]}...",
            }

        return {
            "success": True,
            "updated": True,
            "message": f"ClusterRole {name} deleted",
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"ClusterRole delete error: {str(e)[:100]}...",
        }


def rolebinding_present(
    namespace,
    name,
    role_ref,
    role_ref_kind="Role",
    groups=None,
    users=None,
    service_accounts=None,
    subjects=None,
):
    """
    Ensure a namespaced Kubernetes RoleBinding exists.

    Args:
        namespace (str): Namespace for the RoleBinding.
        name (str): Name of the RoleBinding.
        role_ref (str): Name of the Role or ClusterRole to bind.
        role_ref_kind (str): 'Role' or 'ClusterRole'. Defaults to 'Role'.
        groups (list): Group names to bind (e.g. from an OIDC "groups" claim
            sourced from an LDAP group, surfaced via Keycloak). Bound as kind=Group.
        users (list): Usernames to bind. Bound as kind=User.
        service_accounts (list): "namespace:serviceaccount" strings, or bare
            names (defaulting to this RoleBinding's namespace).
        subjects (list): Raw list of subject dicts for full control, e.g.
            [{"kind": "Group", "name": "k8s-admins"}]. Merged with the
            convenience kwargs above.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic_k8s.rolebinding_present default admins-binding admin \
            role_ref_kind=ClusterRole groups='["k8s-admins"]'
    """
    try:
        _load_k8s_config()
        rbac_api = client.RbacAuthorizationV1Api()

        desired_subjects = _build_rbac_subjects(
            groups=groups,
            users=users,
            service_accounts=service_accounts,
            subjects=subjects,
            default_namespace=namespace,
        )

        exists = False
        try:
            existing = rbac_api.read_namespaced_role_binding(name=name, namespace=namespace)
            exists = True
        except ApiException as e:
            if e.status != 404:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking RoleBinding {name}: {str(e)[:100]}...",
                }
            existing = None

        if (
            exists
            and existing.role_ref.name == role_ref
            and existing.role_ref.kind == role_ref_kind
            and _subject_set(existing.subjects) == _subject_set(desired_subjects)
        ):
            return {
                "success": True,
                "updated": False,
                "message": f"RoleBinding {name} in namespace {namespace} already matches desired state",
            }

        binding_body = client.V1RoleBinding(
            metadata=client.V1ObjectMeta(name=name, namespace=namespace),
            role_ref=client.V1RoleRef(
                api_group="rbac.authorization.k8s.io",
                kind=role_ref_kind,
                name=role_ref,
            ),
            subjects=desired_subjects,
        )

        if not exists:
            rbac_api.create_namespaced_role_binding(namespace=namespace, body=binding_body)
            message = f"RoleBinding {name} created in namespace {namespace}"
        elif existing.role_ref.name != role_ref or existing.role_ref.kind != role_ref_kind:
            # roleRef is immutable; recreate the binding.
            rbac_api.delete_namespaced_role_binding(name=name, namespace=namespace)
            rbac_api.create_namespaced_role_binding(namespace=namespace, body=binding_body)
            message = f"RoleBinding {name} in namespace {namespace} recreated (roleRef changed)"
        else:
            rbac_api.replace_namespaced_role_binding(name=name, namespace=namespace, body=binding_body)
            message = f"RoleBinding {name} in namespace {namespace} updated"

        return {"success": True, "updated": True, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"RoleBinding operation error: {str(e)[:100]}...",
        }


def rolebinding_absent(namespace, name):
    """
    Ensure a namespaced Kubernetes RoleBinding does not exist.

    Args:
        namespace (str): Namespace of the RoleBinding.
        name (str): Name of the RoleBinding.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).
    """
    try:
        _load_k8s_config()
        rbac_api = client.RbacAuthorizationV1Api()
        try:
            rbac_api.delete_namespaced_role_binding(name=name, namespace=namespace)
        except ApiException as e:
            if e.status == 404:
                return {
                    "success": True,
                    "updated": False,
                    "message": f"RoleBinding {name} in namespace {namespace} already absent",
                }
            return {
                "success": False,
                "updated": False,
                "message": f"Error deleting RoleBinding {name}: {str(e)[:100]}...",
            }

        return {
            "success": True,
            "updated": True,
            "message": f"RoleBinding {name} deleted from namespace {namespace}",
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"RoleBinding delete error: {str(e)[:100]}...",
        }


def clusterrolebinding_group_present(
    name,
    cluster_role,
    groups=None,
    users=None,
    service_accounts=None,
    subjects=None,
):
    """
    Ensure a Kubernetes ClusterRoleBinding exists binding a ClusterRole to
    arbitrary subjects (Groups, Users, and/or ServiceAccounts).

    This is a more general counterpart to clusterrolebinding_present (which
    is narrowly scoped to ServiceAccount subjects only and must not be
    changed, since it is already in active use). Use this function for
    bindings driven by OIDC/LDAP Group subjects.

    Args:
        name (str): The name of the ClusterRoleBinding.
        cluster_role (str): The name of the ClusterRole to bind.
        groups (list): Group names to bind (e.g. from an OIDC "groups" claim
            sourced from an LDAP group, surfaced via Keycloak). Bound as kind=Group.
        users (list): Usernames to bind. Bound as kind=User.
        service_accounts (list): "namespace:serviceaccount" strings.
        subjects (list): Raw list of subject dicts for full control.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic_k8s.clusterrolebinding_group_present k8s-admins-binding \
            cluster-admin groups='["k8s-admins"]'
    """
    try:
        _load_k8s_config()
        rbac_api = client.RbacAuthorizationV1Api()

        desired_subjects = _build_rbac_subjects(
            groups=groups,
            users=users,
            service_accounts=service_accounts,
            subjects=subjects,
        )

        exists = False
        try:
            existing = rbac_api.read_cluster_role_binding(name=name)
            exists = True
        except ApiException as e:
            if e.status != 404:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking ClusterRoleBinding {name}: {str(e)[:100]}...",
                }
            existing = None

        if (
            exists
            and existing.role_ref.name == cluster_role
            and existing.role_ref.kind == "ClusterRole"
            and _subject_set(existing.subjects) == _subject_set(desired_subjects)
        ):
            return {
                "success": True,
                "updated": False,
                "message": f"ClusterRoleBinding {name} already matches desired state",
            }

        binding_body = client.V1ClusterRoleBinding(
            metadata=client.V1ObjectMeta(name=name),
            role_ref=client.V1RoleRef(
                api_group="rbac.authorization.k8s.io",
                kind="ClusterRole",
                name=cluster_role,
            ),
            subjects=desired_subjects,
        )

        if not exists:
            rbac_api.create_cluster_role_binding(body=binding_body)
            message = f"ClusterRoleBinding {name} created"
        elif existing.role_ref.name != cluster_role:
            # roleRef is immutable; recreate the binding.
            rbac_api.delete_cluster_role_binding(name=name)
            rbac_api.create_cluster_role_binding(body=binding_body)
            message = f"ClusterRoleBinding {name} recreated (roleRef changed)"
        else:
            rbac_api.replace_cluster_role_binding(name=name, body=binding_body)
            message = f"ClusterRoleBinding {name} updated"

        return {"success": True, "updated": True, "message": message}

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"ClusterRoleBinding operation error: {str(e)[:100]}...",
        }


def clusterrolebinding_group_absent(name):
    """
    Ensure a Kubernetes ClusterRoleBinding does not exist.

    Args:
        name (str): The name of the ClusterRoleBinding.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).
    """
    try:
        _load_k8s_config()
        rbac_api = client.RbacAuthorizationV1Api()
        try:
            rbac_api.delete_cluster_role_binding(name=name)
        except ApiException as e:
            if e.status == 404:
                return {
                    "success": True,
                    "updated": False,
                    "message": f"ClusterRoleBinding {name} already absent",
                }
            return {
                "success": False,
                "updated": False,
                "message": f"Error deleting ClusterRoleBinding {name}: {str(e)[:100]}...",
            }

        return {
            "success": True,
            "updated": True,
            "message": f"ClusterRoleBinding {name} deleted",
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"ClusterRoleBinding delete error: {str(e)[:100]}...",
        }


def serviceaccount_token_secret_present(namespace, name, service_account):
    """
    Ensure a long-lived ServiceAccount token Secret exists (required on Kubernetes 1.24+).

    This is create-only: once the Secret exists, Kubernetes populates the token/ca.crt
    data automatically, so we never attempt to update it.

    Args:
        namespace (str): The namespace for the Secret.
        name (str): The name of the Secret (e.g. 'rook-vault-auth-token').
        service_account (str): The ServiceAccount name to annotate the Secret with.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic_k8s.serviceaccount_token_secret_present rook-ceph rook-vault-auth-token rook-vault-auth
    """
    try:
        _load_k8s_config()

        core_v1_api = client.CoreV1Api()

        # Check if Secret exists (create-only, never update)
        try:
            core_v1_api.read_namespaced_secret(name=name, namespace=namespace)
            return {
                "success": True,
                "updated": False,
                "message": f"ServiceAccount token Secret {name} already exists in namespace {namespace}",
            }
        except ApiException as e:
            if e.status != 404:
                return {
                    "success": False,
                    "updated": False,
                    "message": f"Error checking Secret {name}: {str(e)[:100]}...",
                }

        secret_body = client.V1Secret(
            metadata=client.V1ObjectMeta(
                name=name,
                namespace=namespace,
                annotations={
                    "kubernetes.io/service-account.name": service_account,
                },
            ),
            type="kubernetes.io/service-account-token",
        )
        core_v1_api.create_namespaced_secret(namespace=namespace, body=secret_body)
        return {
            "success": True,
            "updated": True,
            "message": f"ServiceAccount token Secret {name} created in namespace {namespace}",
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"ServiceAccount token Secret operation error: {str(e)[:100]}...",
        }
