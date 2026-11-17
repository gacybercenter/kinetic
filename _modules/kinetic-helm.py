# -*- coding: utf-8 -*-
"""
SaltStack execution module for interacting with Helm to manage repositories and releases.

This module provides functions to add or update Helm repositories and to install or upgrade Helm releases
in Kubernetes, using in-memory dictionaries for values or fetching them from pillar data.
"""

import json
import os
import tempfile

import salt.utils.decorators as decorators

__virtualname__ = "kinetic-helm"


@decorators.memoize
def __virtual__():
    """
    Check if Helm is installed on the system.
    """
    if __salt__["cmd.which"]("helm"):
        return __virtualname__
    return (
        False,
        "Helm is not installed on this system. Please install Helm to use this module.",
    )


def _redact(text, secret):
    """Drop a secret from command output before it can be returned or logged."""
    if not text:
        return ""
    if secret:
        return text.replace(secret, "***")
    return text


def _run_helm(cmd, stdin=None):
    """Run a helm command without a shell. Optional stdin is not placed in argv."""
    kwargs = {"python_shell": False}
    if stdin is not None:
        kwargs["stdin"] = stdin
    result = __salt__["cmd.run_all"](cmd, **kwargs)
    output = (result.get("stdout") or "") + (result.get("stderr") or "")
    return result.get("retcode", 1), output


def _stored_helm_repo(repo_name):
    """Return the repositories.yaml entry for repo_name.

    {} means the config was readable and the repo is absent.
    None means the config could not be read, so stored credentials
    cannot be compared.
    """
    retcode, output = _run_helm(["helm", "env"])
    if retcode != 0:
        return None
    path = ""
    for line in output.splitlines():
        if line.startswith("HELM_REPOSITORY_CONFIG="):
            path = line.split("=", 1)[1].strip().strip("'\"")
            break
    # Missing config is a first add, not an unreadable credential store.
    if not path or not os.path.isfile(path):
        return {}
    try:
        import yaml

        with open(path, "r", encoding="utf-8") as handle:
            data = yaml.safe_load(handle) or {}
    except Exception:
        return None
    for repo in data.get("repositories") or []:
        if isinstance(repo, dict) and repo.get("name") == repo_name:
            return repo
    return {}


def helm_repo_present(
    repo_name,
    repo_url,
    update_cache=True,
    username=None,
    password=None,
    password_pillar=None,
):
    """
    Ensure that a Helm repository is added or updated with the specified URL.

    Authenticated repositories (for example NGC) take ``username`` plus either
    ``password`` or ``password_pillar``. The password is sent to
    ``helm repo add --password-stdin`` and is never placed on the command line.
    Prefer ``password_pillar`` so the secret is resolved on the minion and is
    not rendered into a state file. ``password_pillar`` wins when both are set.

    Args:
        repo_name (str): The name of the Helm repository.
        repo_url (str): The URL of the Helm repository.
        update_cache (bool, optional): Whether to update the Helm repository cache after adding or updating. Defaults to True.
        username (str, optional): Basic-auth username. NGC uses the literal ``$oauthtoken``.
        password (str, optional): Basic-auth password or API key. Prefer ``password_pillar``.
        password_pillar (str, optional): Pillar key (colon-delimited) holding the password or API key.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), and 'message' (str).

    CLI Example:
        salt '*' kinetic-helm.helm_repo_present my-repo https://charts.example.com update_cache=False
        salt '*' kinetic-helm.helm_repo_present runai https://helm.ngc.nvidia.com/nvidia/runai username='$oauthtoken' password_pillar='res-k8s:runai:ngc_api_key'
    """
    try:
        repo_updated = False
        repo_exists = False
        message = f"Configuring Helm repository {repo_name}"

        if password_pillar:
            resolved = __salt__["pillar.get"](password_pillar, None)
            if not isinstance(resolved, str) or not resolved.strip():
                return {
                    "success": False,
                    "updated": False,
                    "message": (
                        f"Helm repository {repo_name} password_pillar "
                        f"{password_pillar} is missing or empty"
                    ),
                }
            password = resolved.strip()
        elif isinstance(password, str):
            password = password.strip()

        if username:
            username = username.strip()
        if bool(username) != bool(password):
            return {
                "success": False,
                "updated": False,
                "message": (
                    f"Helm repository {repo_name} needs both username and "
                    "password (or password_pillar), or neither"
                ),
            }
        if username:
            message += f"; authenticating as {username}"

        # Step 1: Check if repository exists
        repo_list_cmd = ["helm", "repo", "list", "-o", "json"]
        repo_list_result = __salt__["cmd.run"](
            repo_list_cmd, python_shell=False, ignore_retcode=True
        )
        if repo_list_result and "error" not in repo_list_result.lower():
            try:
                repos = json.loads(repo_list_result)
                for repo in repos:
                    if repo.get("name") == repo_name:
                        repo_exists = True
                        if repo.get("url") != repo_url:
                            repo_updated = True
                        break
            except json.JSONDecodeError:
                message += "; Failed to parse Helm repo list output"
                repo_exists = False
        else:
            repo_exists = False

        # helm repo list does not show stored credentials. Compare
        # repositories.yaml so an unchanged API key is not rewritten
        # on every run, and a rotated key is applied.
        needs_add = (not repo_exists) or repo_updated
        if username:
            stored = _stored_helm_repo(repo_name)
            if stored is None:
                needs_add = True
                message += "; stored credentials could not be verified"
            elif (
                stored.get("url") != repo_url
                or stored.get("username") != username
                or stored.get("password") != password
            ):
                needs_add = True
            else:
                needs_add = False
                repo_exists = True

        # Step 2: Add or update repository if necessary
        if needs_add:
            repo_add_cmd = [
                "helm",
                "repo",
                "add",
                repo_name,
                repo_url,
                "--force-update",
            ]
            stdin = None
            if username:
                # List args, not a shell, so a username of $oauthtoken is literal.
                # The secret is stdin, not --password, so it stays out of argv.
                repo_add_cmd.extend(["--username", username, "--password-stdin"])
                stdin = password
            retcode, repo_add_result = _run_helm(repo_add_cmd, stdin=stdin)
            if retcode != 0:
                safe = _redact(repo_add_result, password)
                return {
                    "success": False,
                    "updated": False,
                    "message": (
                        f"Failed to add/update Helm repository {repo_name}: "
                        f"{safe[:200]}; {message}"
                    ),
                }
            repo_updated = True
            message += f"; Helm repository {repo_name} added or updated"

            # Step 3: Update repo cache if update_cache is True
            if update_cache:
                retcode, repo_update_result = _run_helm(["helm", "repo", "update"])
                if retcode != 0:
                    safe = _redact(repo_update_result, password)
                    return {
                        "success": False,
                        "updated": repo_updated,
                        "message": (
                            f"Failed to update Helm repositories: {safe[:200]}; "
                            f"{message}"
                        ),
                    }
                message += "; Helm repositories updated"
            else:
                message += "; Helm repository cache update skipped as per request"
        else:
            if username:
                message += (
                    f"; Helm repository {repo_name} already exists "
                    "and credentials match"
                )
            else:
                message += (
                    f"; Helm repository {repo_name} already exists and up-to-date"
                )

        return {
            "success": True if repo_updated or repo_exists else False,
            "updated": repo_updated,
            "message": _redact(message, password),
        }
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": (
                f"Helm repository operation error for {repo_name}: "
                f"{_redact(str(e), password)[:100]}..."
            ),
        }


def helm_release_present(
    release_name,
    chart_name,
    namespace,
    values_dict=None,
    pillar_key=None,
    version=None,
    wait=True,
    wait_timeout=300,
    wait_interval=10,
    keep_values_file=False,
    set_values=None,
    values_files=None,
):
    """
    Ensure that a Helm release is installed or upgraded with the specified values.
    Values can be provided directly as a dictionary, fetched from a pillar key, or set via --set and --values options.

    Args:
        release_name (str): The name of the Helm release to install or upgrade.
        chart_name (str): The name of the chart to install (format: repo_name/chart_name).
        namespace (str): The Kubernetes namespace to install the release into.
        values_dict (dict, optional): Dictionary of values to pass to the Helm chart. Defaults to None.
        pillar_key (str, optional): Pillar key to fetch values dictionary from. Defaults to None.
        version (str, optional): Specific version of the chart to install. Defaults to None (latest).
        wait (bool, optional): Whether to pass --wait to Helm and block until the release's resources are ready. Defaults to True.
        wait_timeout (int, optional): Maximum time in seconds to wait for Helm release to be ready. Defaults to 300.
        wait_interval (int, optional): Interval in seconds between checks for release readiness. Defaults to 10.
        keep_values_file (bool, optional): If True, retain the temporary values file for debugging. Defaults to False.
        set_values (list, optional): List of key-value pairs to set using --set option (e.g., ["key1=value1", "key2=value2"]). Defaults to None.
        values_files (list, optional): List of paths to additional values files using --values option. Defaults to None.

    Returns:
        dict: A dictionary with 'success' (bool), 'updated' (bool), 'values_file_path' (str, optional), and 'message' (str).

    CLI Example:
        salt '*' kinetic-helm.helm_release_present my-release my-repo/my-chart my-namespace pillar_key='helm:values' set_values='["image.tag=latest"]' values_files='["/path/to/values.yaml"]'
    """
    try:
        release_updated = False
        release_exists = False
        release_matches = False
        values_file_path = ""
        message = f"Configuring Helm release {release_name} in namespace {namespace}"

        is_oci_chart = chart_name.startswith("oci://")

        # Step 1: Fetch values from pillar if pillar_key is provided and values_dict is not
        if pillar_key and not values_dict:
            values_dict = __salt__["pillar.get"](pillar_key, {})
            message += f"; Values fetched from pillar key {pillar_key}"
        elif not values_dict:
            values_dict = {}
            message += f"; No values provided, using default chart values"

        # Step 2: Check if release exists (skip repo logic for OCI charts)
        release_list_cmd = ["helm", "list", "-n", namespace, "-o", "json"]
        release_list_result = __salt__["cmd.run"](
            release_list_cmd, python_shell=False, ignore_retcode=True
        )
        if release_list_result and "error" not in release_list_result.lower():
            try:
                releases = json.loads(release_list_result)
                for release in releases:
                    if release.get("name") == release_name:
                        release_exists = True
                        if (
                            version
                            and release.get("chart") != f"{chart_name}-{version}"
                        ):
                            release_matches = False
                        elif values_dict or set_values or values_files:
                            release_matches = False
                        else:
                            release_matches = True
                        break
            except json.JSONDecodeError:
                message += f"; Failed to parse Helm release list output"
                release_exists = False
        else:
            release_exists = False

        # Step 3: Always use 'helm upgrade --install' to install or upgrade the release
        if not release_exists or not release_matches:
            values_file = None
            if values_dict:
                # Write values to a temporary file as YAML since Helm CLI can handle YAML files
                import yaml  # Requires PyYAML, ensure it's available in the Salt environment

                with tempfile.NamedTemporaryFile(
                    mode="w", delete=False, suffix=".yaml"
                ) as f:
                    yaml.safe_dump(values_dict, f, default_flow_style=False)
                    f.flush()
                    values_file = f.name
                    values_file_path = values_file
                    message += f"; Using temporary values file {values_file}"

            # Build the Helm command as a list to avoid shell=True, always using 'upgrade --install'
            helm_cmd = [
                "helm",
                "upgrade",
                "--install",
                release_name,
                chart_name,
                "-n",
                namespace,
                "--create-namespace",
                f"--timeout={wait_timeout}s",
            ]
            if wait:
                helm_cmd.append("--wait")
            if version:
                helm_cmd.extend(["--version", version])
            if values_file:
                helm_cmd.extend(["--values", values_file])
            if set_values:
                for set_val in set_values:
                    helm_cmd.extend(["--set", set_val])
            if values_files:
                for val_file in values_files:
                    helm_cmd.extend(["--values", val_file])

            helm_result = __salt__["cmd.run"](
                helm_cmd, python_shell=False, ignore_retcode=True
            )

            if values_file and not keep_values_file:
                __salt__["file.remove"](values_file)
                message += f"; Removed temporary values file {values_file}"
            elif values_file and keep_values_file:
                message += f"; Kept temporary values file {values_file} for debugging"

            if helm_result and "error" in helm_result.lower():
                return {
                    "success": False,
                    "updated": False,
                    "values_file_path": values_file_path if keep_values_file else "",
                    "message": f"Failed to upgrade/install Helm release {release_name}: {helm_result}...; {message}",
                }
            release_updated = True
            message += f"; Helm release {release_name} upgraded or installed"
        else:
            message += f"; Helm release {release_name} already exists and up-to-date"

        return {
            "success": True
            if release_updated or (release_exists and release_matches)
            else False,
            "updated": release_updated,
            "values_file_path": values_file_path
            if keep_values_file and values_file_path
            else "",
            "message": message,
        }
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "values_file_path": "",
            "message": f"Helm release operation error for {release_name}: {str(e)[:100]}...",
        }
