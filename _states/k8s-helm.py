# -*- coding: utf-8 -*-
"""
SaltStack state module for managing Helm repositories and releases in Kubernetes.

This module provides states for adding or updating Helm repositories and for installing or upgrading
Helm releases using the kinetic-helm execution module.
"""

__virtualname__ = "k8s_helm"


def __virtual__():
    """
    Check if the kinetic-helm execution module is available.
    """
    if "kinetic-helm.helm_repo_present" in __salt__:
        return __virtualname__
    return (False, "The kinetic-helm execution module is not available.")


def helm_repo_present(name, repo_name, repo_url, update_cache=True):
    """
    Ensure that a Helm repository is added or updated with the specified URL.

    name
        The name of the state (arbitrary, for SaltStack identification).

    repo_name
        The name of the Helm repository to add or update.

    repo_url
        The URL of the Helm repository.

    update_cache
        Optional. Whether to update the Helm repository cache after adding or updating. Defaults to True.

    Example:
    .. code-block:: yaml

        ensure_helm_repo:
          k8s_helm.helm_repo_present:
            - repo_name: bitnami
            - repo_url: https://charts.bitnami.com/bitnami
            - update_cache: False
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic-helm.helm_repo_present"](
            repo_name=repo_name, repo_url=repo_url, update_cache=update_cache
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"repo_updated": True}
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure Helm repository {repo_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def helm_release_present(
    name,
    release_name,
    chart_name,
    namespace,
    values_dict=None,
    pillar_key=None,
    version=None,
    wait_timeout=300,
    wait_interval=10,
    keep_values_file=False,
    set_values=None,
    values_files=None,
):
    """
    Ensure that a Helm release is installed or upgraded in Kubernetes with the specified values.
    Values can be provided directly as a dictionary, fetched from a pillar key, or set via --set and --values options.

    name
        The name of the state (arbitrary, for SaltStack identification).

    release_name
        The name of the Helm release to install or upgrade.

    chart_name
        The name of the chart to install (format: repo_name/chart_name).

    namespace
        The Kubernetes namespace to install the release into.

    values_dict
        Optional. Dictionary of values to pass to the Helm chart. Defaults to None.

    pillar_key
        Optional. Pillar key to fetch values dictionary from. Defaults to None.

    version
        Optional. Specific version of the chart to install. Defaults to None (latest).

    wait_timeout
        Optional. Maximum time in seconds to wait for Helm release to be ready. Defaults to 300.

    wait_interval
        Optional. Interval in seconds between checks for release readiness. Defaults to 10.

    keep_values_file
        Optional. If True, retain the temporary values file for debugging. Defaults to False.

    set_values
        Optional. List of key-value pairs to set using --set option (e.g., ["key1=value1", "key2=value2"]). Defaults to None.

    values_files
        Optional. List of paths to additional values files using --values option. Defaults to None.

    Example:
    .. code-block:: yaml

        ensure_helm_release:
          k8s_helm.helm_release_present:
            - release_name: my-nginx
            - chart_name: bitnami/nginx
            - namespace: default
            - pillar_key: helm:nginx:values
            - version: 9.3.6
            - wait_timeout: 300
            - wait_interval: 10
            - keep_values_file: True
            - set_values:
              - image.tag=latest
              - service.type=LoadBalancer
            - values_files:
              - /path/to/custom-values.yaml
    """
    ret = {"name": name, "result": False, "comment": "", "changes": {}}

    try:
        result = __salt__["kinetic-helm.helm_release_present"](
            release_name=release_name,
            chart_name=chart_name,
            namespace=namespace,
            values_dict=values_dict,
            pillar_key=pillar_key,
            version=version,
            wait_timeout=wait_timeout,
            wait_interval=wait_interval,
            keep_values_file=keep_values_file,
            set_values=set_values,
            values_files=values_files,
        )

        ret["result"] = result["success"]
        ret["comment"] = result["message"]
        if result["updated"]:
            ret["changes"] = {"release_updated": True}
        if result.get("values_file_path"):
            ret["comment"] += f"; Values file retained at: {result['values_file_path']}"
            ret["changes"]["values_file_path"] = result["values_file_path"]
        else:
            ret[
                "changes"
            ] = {}  # Explicitly empty to prevent SaltStack from reporting changes unnecessarily

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure Helm release {release_name}: {str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret
