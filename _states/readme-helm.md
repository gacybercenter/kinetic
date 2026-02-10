# K8s-Helm State Module

## Overview

The `k8s-helm` state module is a SaltStack state module designed to manage Helm repositories and releases in Kubernetes. This module leverages the `kinetic-helm` execution module to provide declarative state management for Helm operations, allowing for automated configuration and deployment of Kubernetes applications through SaltStack states.

## Prerequisites

- **Helm**: Ensure that Helm is installed on the system where this module is executed. The underlying `kinetic-helm` execution module checks for the presence of the `helm` command-line tool.
- **Kinetic-Helm Execution Module**: This state module depends on the `kinetic-helm` execution module being available in SaltStack.

## Installation

To use this module, place it in the SaltStack states directory under `_states/`. Sync the module to your Salt minions using:

```bash
salt '*' saltutil.sync_states
```

## States

### `helm_repo_present(name, repo_name, repo_url, update_cache=True)`

Ensures that a Helm repository is added or updated with the specified URL.

- **Parameters**:
  - `name`: The name of the state (arbitrary, for SaltStack identification).
  - `repo_name` (str): The name of the Helm repository to add or update.
  - `repo_url` (str): The URL of the Helm repository.
  - `update_cache` (bool, optional): Whether to update the Helm repository cache after adding or updating. Defaults to True.

- **Returns**: A dictionary containing:
  - `name` (str): The name of the state.
  - `result` (bool): Indicates if the operation was successful.
  - `comment` (str): A detailed message about the operation.
  - `changes` (dict): Indicates if the repository was updated (`repo_updated`: True if updated).

- **Example**:
  ```yaml
  ensure_helm_repo:
    k8s_helm.helm_repo_present:
      - repo_name: bitnami
      - repo_url: https://charts.bitnami.com/bitnami
      - update_cache: False
  ```

### `helm_release_present(name, release_name, chart_name, namespace, values_dict=None, pillar_key=None, version=None, wait_timeout=300, wait_interval=10, keep_values_file=False)`

Ensures that a Helm release is installed or upgraded in Kubernetes with the specified values. Values can be provided directly as a dictionary or fetched from a pillar key.

- **Parameters**:
  - `name`: The name of the state (arbitrary, for SaltStack identification).
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
  - `name` (str): The name of the state.
  - `result` (bool): Indicates if the operation was successful.
  - `comment` (str): A detailed message about the operation, including the path to the retained values file if applicable.
  - `changes` (dict): Indicates if the release was updated (`release_updated`: True if updated) and includes `values_file_path` if a values file was retained.

- **Example**:
  ```yaml
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
  ```

## Usage Notes

- This module integrates with the `kinetic-helm` execution module to perform Helm operations declaratively via SaltStack states.
- Ensure that the Salt minion has the necessary permissions to execute Helm commands and access the Kubernetes cluster.
- The module supports both direct dictionary inputs for Helm values and fetching from Salt pillar data, providing flexibility in configuration management.
- Temporary files for Helm values are created during release operations and can be optionally retained for debugging purposes.

## Contributing

If you encounter any issues or have suggestions for improvements, please open an issue or submit a pull request to the repository hosting this module.

## License

This module is distributed under the same license as SaltStack. Ensure compliance with SaltStack's licensing terms when using or distributing this module.
