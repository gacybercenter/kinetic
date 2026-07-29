# -*- coding: utf-8 -*-
"""
SaltStack execution module for HashiCorp Vault management.

This module manages HashiCorp Vault via its direct HTTP API (not kubectl exec).
It stores the Vault init material (root token, unseal keys) in a Kubernetes
Secret, which acts as the source of truth for later authenticated calls.
It follows the pattern established in kinetic-rook.py.
"""

import base64
import json
import logging

import salt.utils.decorators as decorators

try:
    import requests
    import urllib3
    from kubernetes import client, config
    from kubernetes.client.rest import ApiException

    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    HAS_LIBS = True
except ImportError:
    HAS_LIBS = False

log = logging.getLogger(__name__)

__virtualname__ = "kinetic_vault"

# Default transport routes through the Kubernetes API server service proxy,
# so the Vault API does not need to be exposed outside the cluster.
# Format: k8s://<namespace>/<service>:<port>
# A regular https:// address is also supported for direct access.
DEFAULT_VAULT_ADDR = "k8s://rook-ceph/vault:8200"
DEFAULT_KUBERNETES_HOST = "https://kubernetes.default.svc.cluster.local"


@decorators.memoize
def __virtual__():
    """
    Check if the requests and kubernetes python libraries are available.
    """
    if HAS_LIBS:
        return "kinetic_vault"
    return (
        False,
        'The requests and/or kubernetes python libraries are not installed. '
        'Please install them using "pip install requests kubernetes".'
    )


def _load_k8s_config():
    """Load Kubernetes configuration, preferring in-cluster config then kubeconfig."""
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()


def _vault_request_via_k8s_proxy(method, vault_addr, path, token=None, payload=None):
    """
    Make an HTTP request against the Vault API through the Kubernetes API
    server service proxy. This works even when the Vault API is not exposed
    outside the cluster; only Kubernetes API access is required.

    vault_addr format: k8s://<namespace>/<service>:<port>

    Returns:
        tuple: (status_code, json_body_or_None)
    """
    _load_k8s_config()

    # Parse k8s://<namespace>/<service>:<port>
    addr = vault_addr[len("k8s://"):]
    svc_namespace, service_port = addr.split("/", 1)

    api_client = client.ApiClient()
    proxy_path = (
        f"/api/v1/namespaces/{svc_namespace}/services/"
        f"https:{service_port}/proxy/v1/{path}"
    )

    header_params = {"Accept": "application/json"}
    if token:
        header_params["X-Vault-Token"] = token
    if payload is not None:
        header_params["Content-Type"] = "application/json"

    try:
        resp = api_client.call_api(
            proxy_path,
            method.upper(),
            header_params=header_params,
            body=payload,
            auth_settings=["BearerToken"],
            _preload_content=False,
            _return_http_data_only=True,
            _request_timeout=15,
        )
        status_code = resp.status
        raw = resp.data
    except ApiException as e:
        # Vault intentionally returns non-2xx codes (e.g. sys/health 429/503);
        # the kubernetes client raises for those, so unwrap the response.
        status_code = e.status
        raw = e.body

    try:
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8")
        body = json.loads(raw) if raw else None
    except (ValueError, TypeError):
        body = None
    return status_code, body


def _vault_request(method, vault_addr, path, token=None, payload=None, verify=False):
    """
    Make an HTTP request against the Vault API.

    Supports two transports based on the vault_addr scheme:
    - k8s://<namespace>/<service>:<port>  -> Kubernetes API server service proxy
      (use when the Vault API is not exposed outside the cluster)
    - https://host:port                   -> direct HTTPS

    Returns:
        tuple: (status_code, json_body_or_None)
    """
    if vault_addr.startswith("k8s://"):
        return _vault_request_via_k8s_proxy(
            method, vault_addr, path, token=token, payload=payload
        )

    headers = {}
    if token:
        headers["X-Vault-Token"] = token
    url = f"{vault_addr}/v1/{path}"
    resp = requests.request(
        method,
        url,
        headers=headers,
        json=payload,
        verify=verify,
        timeout=15,
    )
    try:
        body = resp.json()
    except ValueError:
        body = None
    return resp.status_code, body


def _http_error(action, status_code, body):
    """Build a standard failure return dict for an unexpected HTTP response."""
    text = json.dumps(body) if body is not None else ""
    return {
        "success": False,
        "updated": False,
        "message": f"{action} failed with HTTP {status_code}: {text[:200]}",
    }


def _to_list(value):
    """Normalize a comma-separated string or list into a list of strings."""
    if value is None:
        return []
    if isinstance(value, str):
        return [item.strip() for item in value.split(",") if item.strip()]
    return [str(item) for item in value]


def _get_token(token, namespace, secret_name):
    """Return the provided token, or look up the root token from Kubernetes."""
    if token:
        return token
    return get_root_token(namespace=namespace, secret_name=secret_name)


def _upsert_k8s_secret(core_api, namespace, secret_name, string_data):
    """Create or replace a Kubernetes Secret with the given stringData."""
    body = client.V1Secret(
        metadata=client.V1ObjectMeta(name=secret_name, namespace=namespace),
        string_data=string_data,
    )
    try:
        core_api.read_namespaced_secret(secret_name, namespace)
        core_api.replace_namespaced_secret(secret_name, namespace, body)
        return "replaced"
    except ApiException as e:
        if e.status == 404:
            core_api.create_namespaced_secret(namespace, body)
            return "created"
        raise


def initialize(
    vault_addr=DEFAULT_VAULT_ADDR,
    namespace="rook-ceph",
    secret_name="vault-init",
    kms_unseal=True,
    key_shares=5,
    key_threshold=3,
    verify=False,
):
    """
    Initialize Vault and store the init material in a Kubernetes Secret.

    The full init response (root token and unseal/recovery keys) is stored
    in the Secret secret_name in namespace under the keys
    root_token and init.json. This Secret is the source of truth
    for the root token.

    When kms_unseal is True (KMS auto-unseal, e.g. Azure Key Vault),
    secret_shares/secret_threshold must NOT be sent - the seal type does not
    accept them. Recovery keys are generated instead, using key_shares and
    key_threshold as recovery_shares/recovery_threshold.

    Args:
        vault_addr (str): Vault API address (default: k8s://rook-ceph/vault:8200)
        namespace (str): Namespace for the init Secret (default: rook-ceph)
        secret_name (str): Name of the init Secret (default: vault-init)
        kms_unseal (bool): Vault uses a KMS auto-unseal seal such as Azure
            Key Vault (default: True). Sends recovery_shares/recovery_threshold
            instead of secret_shares/secret_threshold.
        key_shares (int): Number of key shares / recovery shares (default: 5)
        key_threshold (int): Key / recovery threshold (default: 3)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message
    """
    try:
        status_code, body = _vault_request(
            "GET", vault_addr, "sys/init", verify=verify
        )
        if status_code != 200 or body is None:
            return _http_error("Checking Vault init status", status_code, body)

        if body.get("initialized"):
            return {
                "success": True,
                "updated": False,
                "message": "Vault is already initialized",
            }

        if kms_unseal:
            # KMS auto-unseal (e.g. Azure Key Vault): secret_shares/threshold
            # are not applicable; recovery keys are generated instead.
            payload = {
                "recovery_shares": key_shares,
                "recovery_threshold": key_threshold,
            }
        else:
            payload = {
                "secret_shares": key_shares,
                "secret_threshold": key_threshold,
            }
        status_code, body = _vault_request(
            "PUT", vault_addr, "sys/init", payload=payload, verify=verify
        )
        if status_code != 200 or body is None:
            return _http_error("Initializing Vault", status_code, body)

        root_token = body.get("root_token")
        if not root_token:
            return {
                "success": False,
                "updated": False,
                "message": "Vault init response did not contain a root_token",
            }

        _load_k8s_config()
        core_api = client.CoreV1Api()
        action = _upsert_k8s_secret(
            core_api,
            namespace,
            secret_name,
            {
                "root_token": root_token,
                "init.json": json.dumps(body),
            },
        )

        unseal_note = (
            "vault will auto-unseal (KMS)" if kms_unseal else "manual unseal required"
        )
        return {
            "success": True,
            "updated": True,
            "message": (
                f"Vault initialized; init material {action} in secret "
                f"{namespace}/{secret_name}; {unseal_note}"
            ),
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to initialize Vault: {str(e)}",
        }


def get_root_token(namespace="rook-ceph", secret_name="vault-init"):
    """
    Read the Vault root token from the Kubernetes init Secret.

    This enables dynamic runtime lookup from jinja:
    salt['kinetic_vault.get_root_token']()

    Args:
        namespace (str): Namespace of the init Secret (default: rook-ceph)
        secret_name (str): Name of the init Secret (default: vault-init)

    Returns:
        str: The decoded root token, or None if it cannot be read.
    """
    try:
        _load_k8s_config()
        core_api = client.CoreV1Api()
        secret = core_api.read_namespaced_secret(secret_name, namespace)
        data = secret.data or {}
        if "root_token" not in data:
            return None
        return base64.b64decode(data["root_token"]).decode("utf-8")
    except Exception as e:
        log.debug(
            "Unable to read Vault root token from %s/%s: %s",
            namespace, secret_name, e,
        )
        return None


def status(vault_addr=DEFAULT_VAULT_ADDR, verify=False):
    """
    Return the Vault health status.

    sys/health intentionally returns different HTTP status codes
    (200/429/472/473/501/503) depending on the server state; all are
    accepted.

    Args:
        vault_addr (str): Vault API address (default: https://vault.rook-ceph.svc:8200)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, initialized, sealed, message
    """
    try:
        status_code, body = _vault_request(
            "GET", vault_addr, "sys/health", verify=verify
        )
        if body is None:
            return {
                "success": False,
                "updated": False,
                "message": (
                    f"Vault health check returned HTTP {status_code} "
                    f"with no JSON body"
                ),
            }

        initialized = body.get("initialized", False)
        sealed = body.get("sealed", True)
        return {
            "success": True,
            "initialized": initialized,
            "sealed": sealed,
            "message": (
                f"Vault health: initialized={initialized}, sealed={sealed} "
                f"(HTTP {status_code})"
            ),
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to get Vault status: {str(e)}",
        }


def auth_method_present(
    method="kubernetes",
    path=None,
    description="",
    vault_addr=DEFAULT_VAULT_ADDR,
    token=None,
    namespace="rook-ceph",
    secret_name="vault-init",
    verify=False,
):
    """
    Ensure a Vault auth method is enabled at the given path.

    Args:
        method (str): Auth method type (default: kubernetes)
        path (str): Mount path for the auth method (default: same as method)
        description (str): Description for the auth method
        vault_addr (str): Vault API address (default: https://vault.rook-ceph.svc:8200)
        token (str): Vault token; looked up from the init Secret if not given
        namespace (str): Namespace of the init Secret (default: rook-ceph)
        secret_name (str): Name of the init Secret (default: vault-init)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message
    """
    try:
        if path is None:
            path = method

        token = _get_token(token, namespace, secret_name)
        if not token:
            return {
                "success": False,
                "updated": False,
                "message": (
                    f"Unable to obtain Vault root token from secret "
                    f"{namespace}/{secret_name}"
                ),
            }

        status_code, body = _vault_request(
            "GET", vault_addr, "sys/auth", token=token, verify=verify
        )
        if status_code != 200 or body is None:
            return _http_error("Listing Vault auth methods", status_code, body)

        mounts = body.get("data") or body
        if f"{path}/" in mounts:
            return {
                "success": True,
                "updated": False,
                "message": f"Auth method {method} already enabled at {path}/",
            }

        payload = {"type": method, "description": description}
        status_code, body = _vault_request(
            "POST", vault_addr, f"sys/auth/{path}",
            token=token, payload=payload, verify=verify,
        )
        if status_code not in (200, 204):
            return _http_error(
                f"Enabling auth method {method} at {path}/", status_code, body
            )

        return {
            "success": True,
            "updated": True,
            "message": f"Auth method {method} enabled at {path}/",
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure auth method {method}: {str(e)}",
        }


def kubernetes_auth_configure(
    kubernetes_host=None,
    sa_secret_name=None,
    sa_namespace="rook-ceph",
    issuer=None,
    mount="kubernetes",
    vault_addr=DEFAULT_VAULT_ADDR,
    token=None,
    namespace="rook-ceph",
    secret_name="vault-init",
    verify=False,
):
    """
    Configure the Vault kubernetes auth method.

    Pulls the ServiceAccount JWT (key token) and CA certificate
    (key ca.crt) from the Kubernetes Secret sa_secret_name in
    sa_namespace and writes them to auth/{mount}/config.

    Args:
        kubernetes_host (str): Kubernetes API address
            (default: https://kubernetes.default.svc.cluster.local)
        sa_secret_name (str): Name of the ServiceAccount token Secret
        sa_namespace (str): Namespace of the ServiceAccount Secret (default: rook-ceph)
        issuer (str): Token issuer (default: https://kubernetes.default.svc.cluster.local)
        mount (str): Auth mount path (default: kubernetes)
        vault_addr (str): Vault API address (default: https://vault.rook-ceph.svc:8200)
        token (str): Vault token; looked up from the init Secret if not given
        namespace (str): Namespace of the init Secret (default: rook-ceph)
        secret_name (str): Name of the init Secret (default: vault-init)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message
    """
    try:
        if not sa_secret_name:
            return {
                "success": False,
                "updated": False,
                "message": "sa_secret_name is required",
            }

        if kubernetes_host is None:
            kubernetes_host = DEFAULT_KUBERNETES_HOST
        if issuer is None:
            issuer = DEFAULT_KUBERNETES_HOST

        token = _get_token(token, namespace, secret_name)
        if not token:
            return {
                "success": False,
                "updated": False,
                "message": (
                    f"Unable to obtain Vault root token from secret "
                    f"{namespace}/{secret_name}"
                ),
            }

        _load_k8s_config()
        core_api = client.CoreV1Api()
        sa_secret = core_api.read_namespaced_secret(sa_secret_name, sa_namespace)
        data = sa_secret.data or {}
        if "token" not in data or "ca.crt" not in data:
            return {
                "success": False,
                "updated": False,
                "message": (
                    f"Secret {sa_namespace}/{sa_secret_name} is missing the "
                    f"token and/or ca.crt keys"
                ),
            }

        reviewer_jwt = base64.b64decode(data["token"]).decode("utf-8")
        ca_cert = base64.b64decode(data["ca.crt"]).decode("utf-8")

        status_code, body = _vault_request(
            "GET", vault_addr, f"auth/{mount}/config", token=token, verify=verify
        )
        if status_code == 200 and body is not None:
            existing = body.get("data", {})
            if (
                existing.get("kubernetes_host") == kubernetes_host
                and existing.get("issuer") == issuer
            ):
                return {
                    "success": True,
                    "updated": False,
                    "message": (
                        f"Kubernetes auth at {mount}/ already configured "
                        f"for {kubernetes_host}"
                    ),
                }

        payload = {
            "token_reviewer_jwt": reviewer_jwt,
            "kubernetes_host": kubernetes_host,
            "kubernetes_ca_cert": ca_cert,
            "issuer": issuer,
        }
        status_code, body = _vault_request(
            "POST", vault_addr, f"auth/{mount}/config",
            token=token, payload=payload, verify=verify,
        )
        if status_code not in (200, 204):
            return _http_error(
                f"Configuring kubernetes auth at {mount}/", status_code, body
            )

        return {
            "success": True,
            "updated": True,
            "message": (
                f"Kubernetes auth at {mount}/ configured for {kubernetes_host}"
            ),
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to configure kubernetes auth: {str(e)}",
        }


def secrets_engine_present(
    path="rook",
    engine_type="kv",
    options=None,
    vault_addr=DEFAULT_VAULT_ADDR,
    token=None,
    namespace="rook-ceph",
    secret_name="vault-init",
    verify=False,
):
    """
    Ensure a Vault secrets engine is mounted at the given path.

    Args:
        path (str): Mount path for the secrets engine (default: rook)
        engine_type (str): Secrets engine type (default: kv)
        options (dict): Engine options (default: version 2 for kv)
        vault_addr (str): Vault API address (default: https://vault.rook-ceph.svc:8200)
        token (str): Vault token; looked up from the init Secret if not given
        namespace (str): Namespace of the init Secret (default: rook-ceph)
        secret_name (str): Name of the init Secret (default: vault-init)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message
    """
    try:
        if options is None and engine_type == "kv":
            options = {"version": "2"}

        token = _get_token(token, namespace, secret_name)
        if not token:
            return {
                "success": False,
                "updated": False,
                "message": (
                    f"Unable to obtain Vault root token from secret "
                    f"{namespace}/{secret_name}"
                ),
            }

        status_code, body = _vault_request(
            "GET", vault_addr, "sys/mounts", token=token, verify=verify
        )
        if status_code != 200 or body is None:
            return _http_error("Listing Vault secrets engines", status_code, body)

        mounts = body.get("data") or body
        if f"{path}/" in mounts:
            return {
                "success": True,
                "updated": False,
                "message": f"Secrets engine already mounted at {path}/",
            }

        payload = {"type": engine_type, "options": options}
        status_code, body = _vault_request(
            "POST", vault_addr, f"sys/mounts/{path}",
            token=token, payload=payload, verify=verify,
        )
        if status_code not in (200, 204):
            return _http_error(
                f"Mounting secrets engine {engine_type} at {path}/",
                status_code, body,
            )

        return {
            "success": True,
            "updated": True,
            "message": f"Secrets engine {engine_type} mounted at {path}/",
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure secrets engine at {path}: {str(e)}",
        }


def policy_present(
    name,
    policy,
    vault_addr=DEFAULT_VAULT_ADDR,
    token=None,
    namespace="rook-ceph",
    secret_name="vault-init",
    verify=False,
):
    """
    Ensure a Vault ACL policy exists with the given content.

    Args:
        name (str): Policy name
        policy (str): Policy document (HCL)
        vault_addr (str): Vault API address (default: https://vault.rook-ceph.svc:8200)
        token (str): Vault token; looked up from the init Secret if not given
        namespace (str): Namespace of the init Secret (default: rook-ceph)
        secret_name (str): Name of the init Secret (default: vault-init)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message
    """
    try:
        token = _get_token(token, namespace, secret_name)
        if not token:
            return {
                "success": False,
                "updated": False,
                "message": (
                    f"Unable to obtain Vault root token from secret "
                    f"{namespace}/{secret_name}"
                ),
            }

        status_code, body = _vault_request(
            "GET", vault_addr, f"sys/policies/acl/{name}",
            token=token, verify=verify,
        )
        if status_code == 200 and body is not None:
            existing = body.get("data", {}).get("policy", "")
            if existing.strip() == policy.strip():
                return {
                    "success": True,
                    "updated": False,
                    "message": f"Policy {name} already matches desired content",
                }

        payload = {"policy": policy}
        status_code, body = _vault_request(
            "PUT", vault_addr, f"sys/policies/acl/{name}",
            token=token, payload=payload, verify=verify,
        )
        if status_code not in (200, 204):
            return _http_error(f"Writing policy {name}", status_code, body)

        return {
            "success": True,
            "updated": True,
            "message": f"Policy {name} written",
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure policy {name}: {str(e)}",
        }


def kubernetes_role_present(
    role_name,
    bound_service_account_names,
    bound_service_account_namespaces,
    policies,
    ttl="1440h",
    audience="https://kubernetes.default.svc.cluster.local",
    mount="kubernetes",
    vault_addr=DEFAULT_VAULT_ADDR,
    token=None,
    namespace="rook-ceph",
    secret_name="vault-init",
    verify=False,
):
    """
    Ensure a Vault kubernetes auth role exists with the given bindings.

    Args:
        role_name (str): Name of the kubernetes auth role
        bound_service_account_names (list|str): ServiceAccount names (list or CSV)
        bound_service_account_namespaces (list|str): ServiceAccount namespaces (list or CSV)
        policies (list|str): Policies to attach (list or CSV)
        ttl (str): Token TTL (default: 1440h)
        audience (str): Token audience
            (default: https://kubernetes.default.svc.cluster.local)
        mount (str): Auth mount path (default: kubernetes)
        vault_addr (str): Vault API address (default: https://vault.rook-ceph.svc:8200)
        token (str): Vault token; looked up from the init Secret if not given
        namespace (str): Namespace of the init Secret (default: rook-ceph)
        secret_name (str): Name of the init Secret (default: vault-init)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message
    """
    try:
        bound_names = _to_list(bound_service_account_names)
        bound_namespaces = _to_list(bound_service_account_namespaces)
        policy_list = _to_list(policies)

        token = _get_token(token, namespace, secret_name)
        if not token:
            return {
                "success": False,
                "updated": False,
                "message": (
                    f"Unable to obtain Vault root token from secret "
                    f"{namespace}/{secret_name}"
                ),
            }

        status_code, body = _vault_request(
            "GET", vault_addr, f"auth/{mount}/role/{role_name}",
            token=token, verify=verify,
        )
        if status_code == 200 and body is not None:
            existing = body.get("data", {})
            names_match = sorted(
                _to_list(existing.get("bound_service_account_names"))
            ) == sorted(bound_names)
            namespaces_match = sorted(
                _to_list(existing.get("bound_service_account_namespaces"))
            ) == sorted(bound_namespaces)
            policies_match = sorted(
                _to_list(existing.get("policies"))
            ) == sorted(policy_list)
            if names_match and namespaces_match and policies_match:
                return {
                    "success": True,
                    "updated": False,
                    "message": (
                        f"Kubernetes auth role {role_name} already matches "
                        f"desired state"
                    ),
                }

        payload = {
            "bound_service_account_names": bound_names,
            "bound_service_account_namespaces": bound_namespaces,
            "policies": policy_list,
            "audience": audience,
            "ttl": ttl,
        }
        status_code, body = _vault_request(
            "POST", vault_addr, f"auth/{mount}/role/{role_name}",
            token=token, payload=payload, verify=verify,
        )
        if status_code not in (200, 204):
            return _http_error(
                f"Writing kubernetes auth role {role_name}", status_code, body
            )

        return {
            "success": True,
            "updated": True,
            "message": f"Kubernetes auth role {role_name} written at {mount}/",
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": (
                f"Failed to ensure kubernetes auth role {role_name}: {str(e)}"
            ),
        }


def approle_present(
    role_name,
    token_policies,
    token_ttl="1h",
    token_max_ttl="4h",
    mount="approle",
    vault_addr=DEFAULT_VAULT_ADDR,
    token=None,
    namespace="rook-ceph",
    secret_name="vault-init",
    verify=False,
):
    """
    Ensure a Vault AppRole exists with the given token policies.

    Args:
        role_name (str): Name of the AppRole
        token_policies (list|str): Policies for issued tokens (list or CSV)
        token_ttl (str): Token TTL (default: 1h)
        token_max_ttl (str): Token max TTL (default: 4h)
        mount (str): Auth mount path (default: approle)
        vault_addr (str): Vault API address (default: https://vault.rook-ceph.svc:8200)
        token (str): Vault token; looked up from the init Secret if not given
        namespace (str): Namespace of the init Secret (default: rook-ceph)
        secret_name (str): Name of the init Secret (default: vault-init)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message
    """
    try:
        policy_list = _to_list(token_policies)

        token = _get_token(token, namespace, secret_name)
        if not token:
            return {
                "success": False,
                "updated": False,
                "message": (
                    f"Unable to obtain Vault root token from secret "
                    f"{namespace}/{secret_name}"
                ),
            }

        status_code, body = _vault_request(
            "GET", vault_addr, f"auth/{mount}/role/{role_name}",
            token=token, verify=verify,
        )
        if status_code == 200 and body is not None:
            existing = body.get("data", {})
            if sorted(_to_list(existing.get("token_policies"))) == sorted(policy_list):
                return {
                    "success": True,
                    "updated": False,
                    "message": f"AppRole {role_name} already matches desired state",
                }

        payload = {
            "token_policies": policy_list,
            "token_ttl": token_ttl,
            "token_max_ttl": token_max_ttl,
        }
        status_code, body = _vault_request(
            "POST", vault_addr, f"auth/{mount}/role/{role_name}",
            token=token, payload=payload, verify=verify,
        )
        if status_code not in (200, 204):
            return _http_error(f"Writing AppRole {role_name}", status_code, body)

        return {
            "success": True,
            "updated": True,
            "message": f"AppRole {role_name} written at {mount}/",
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure AppRole {role_name}: {str(e)}",
        }


def approle_credentials_to_secret(
    role_name,
    k8s_secret_name,
    k8s_namespace="rook-ceph",
    mount="approle",
    regenerate=False,
    vault_addr=DEFAULT_VAULT_ADDR,
    token=None,
    namespace="rook-ceph",
    secret_name="vault-init",
    verify=False,
):
    """
    Fetch AppRole credentials and store them in a Kubernetes Secret.

    Reads the role-id and generates a secret-id for the AppRole, then
    stores both in the Kubernetes Secret k8s_secret_name (stringData
    keys role_id and secret_id). If the Secret already exists and
    regenerate is False, nothing is changed.

    Args:
        role_name (str): Name of the AppRole
        k8s_secret_name (str): Name of the Kubernetes Secret to store credentials in
        k8s_namespace (str): Namespace for the Kubernetes Secret (default: rook-ceph)
        mount (str): Auth mount path (default: approle)
        regenerate (bool): Regenerate credentials even if the Secret exists (default: False)
        vault_addr (str): Vault API address (default: https://vault.rook-ceph.svc:8200)
        token (str): Vault token; looked up from the init Secret if not given
        namespace (str): Namespace of the init Secret (default: rook-ceph)
        secret_name (str): Name of the init Secret (default: vault-init)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message
    """
    try:
        _load_k8s_config()
        core_api = client.CoreV1Api()

        exists = False
        try:
            core_api.read_namespaced_secret(k8s_secret_name, k8s_namespace)
            exists = True
        except ApiException as e:
            if e.status != 404:
                raise

        if exists and not regenerate:
            return {
                "success": True,
                "updated": False,
                "message": (
                    f"AppRole credentials for {role_name} already stored in "
                    f"secret {k8s_namespace}/{k8s_secret_name}"
                ),
            }

        token = _get_token(token, namespace, secret_name)
        if not token:
            return {
                "success": False,
                "updated": False,
                "message": (
                    f"Unable to obtain Vault root token from secret "
                    f"{namespace}/{secret_name}"
                ),
            }

        status_code, body = _vault_request(
            "GET", vault_addr, f"auth/{mount}/role/{role_name}/role-id",
            token=token, verify=verify,
        )
        if status_code != 200 or body is None:
            return _http_error(
                f"Reading role-id for AppRole {role_name}", status_code, body
            )
        role_id = body.get("data", {}).get("role_id")

        status_code, body = _vault_request(
            "POST", vault_addr, f"auth/{mount}/role/{role_name}/secret-id",
            token=token, verify=verify,
        )
        if status_code != 200 or body is None:
            return _http_error(
                f"Generating secret-id for AppRole {role_name}", status_code, body
            )
        secret_id = body.get("data", {}).get("secret_id")

        if not role_id or not secret_id:
            return {
                "success": False,
                "updated": False,
                "message": (
                    f"Vault did not return complete credentials for AppRole "
                    f"{role_name}"
                ),
            }

        action = _upsert_k8s_secret(
            core_api,
            k8s_namespace,
            k8s_secret_name,
            {"role_id": role_id, "secret_id": secret_id},
        )

        return {
            "success": True,
            "updated": True,
            "message": (
                f"AppRole credentials for {role_name} {action} in secret "
                f"{k8s_namespace}/{k8s_secret_name}"
            ),
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": (
                f"Failed to store AppRole credentials for {role_name}: {str(e)}"
            ),
        }
