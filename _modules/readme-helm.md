# Kinetic-Helm Module

## Overview

The `kinetic-helm` module is a SaltStack execution module designed to interact with Helm, the package manager for Kubernetes. This module facilitates the management of Helm repositories and releases directly from SaltStack, allowing for automated deployment and configuration of Kubernetes applications.

## Prerequisites

- **Helm**: Ensure that Helm is installed on the system where this module is executed. The module checks for the presence of the `helm` command-line tool and will not load if it is not found.

## Functions

### `helm_repo_present(repo_name, repo_url, update_cache=True)`

Ensures that a Helm repository is added or updated with the specified URL.

- **Parameters**:
  - `repo_name` (str): The name of the Helm repository.
  - `repo_url` (str): The URL of the Helm repository.
  - `update_cache` (bool, optional): Whether to update the Helm repository cache after adding or updating. Defaults to True.

- **Returns**: A dictionary containing:
  - `success` (bool): Indicates if the operation was successful.
  - `updated` (bool): Indicates if the repository was added or updated.
  - `message` (str): A detailed message about the operation.

- **CLI Example**:
  ```bash
  salt '*' kinetic-helm.helm_repo_present my-repo https://charts.example.com update_cache=False
  ```

### `helm_release_present(release_name, chart_name, namespace, values_dict=None, pillar_key=None, version=None, wait_timeout=300, wait_interval=10, keep_values_file=False)`

Ensures that a Helm release is installed or upgraded with the specified values. Values can be provided directly as a dictionary or fetched from a pillar key.

- **Parameters**:
  - `release_name` (str): The name of the Helm release to install or upgrade.
  - `chart_name` (str): The name of the chart to install (format: `repo_name/chart_name`).
  - `namespace` (str): The Kubernetes namespace to install the release into.
  - `values_dict` (dict, optional): Dictionary of values to pass to the Helm chart. Defaults to None.
  - `pillar_key` (str, optional): Pillar key to fetch values dictionary from. Defaults to None.
  - `version` (str, optional): Specific version of the chart to install. Defaults to None (latest).
  - `wait_timeout` (int, optional): Maximum time in seconds to wait for Helm release to be ready. Defaults to 300.
  - `wait_interval` (int, optional): Interval in seconds between checks for release readiness. Defaults to 10.
  - `keep_values_file` (bool, optional): If True, retain the temporary values file for debugging. Defaults to False.

- **Returns**: A dictionary containing:
  - `success` (bool): Indicates if the operation was successful.
  - `updated` (bool): Indicates if the release was installed or upgraded.
  - `values_file_path` (str, optional): Path to the temporary values file if kept for debugging.
  - `message` (str): A detailed message about the operation.

- **CLI Example**:
  ```bash
  salt '*' kinetic-helm.helm_release_present my-release my-repo/my-chart my-namespace pillar_key='helm:values' keep_values_file=True
  ```

## Usage Notes

- This module uses the `helm` CLI under the hood, so ensure that the Salt minion has the necessary permissions to execute Helm commands and access the Kubernetes cluster.
- The module supports both direct dictionary inputs for Helm values and fetching from Salt pillar data, providing flexibility in configuration management.
- Temporary files for Helm values are created and can be optionally retained for debugging purposes.
```
