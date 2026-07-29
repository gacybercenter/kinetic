# -*- coding: utf-8 -*-
"""
SaltStack state module for HashiCorp Vault management.

This module provides states to manage Vault via the kinetic_vault
execution module (direct HTTP API). It complements the existing k8s
module by providing Vault-specific states.
"""

def __virtual__():
    """
    Only load if the kinetic_vault execution module is available.
    """
    if "kinetic_vault.status" in __salt__:
        return "vault"
    return (
        False,
        "kinetic_vault execution module not available"
    )


def _state_ret(name):
    """Return a standard SaltStack state return dict."""
    return {"name": name, "result": False, "comment": "", "changes": {}}


def initialized(
    name,
    vault_addr="k8s://rook-ceph/vault:8200",
    namespace="rook-ceph",
    secret_name="vault-init",
    kms_unseal=True,
    key_shares=5,
    key_threshold=3,
    verify=False,
):
    """
    Ensure Vault is initialized, storing init material in a Kubernetes Secret.

    name
        The name of the state.

    vault_addr
        Vault API address (default: k8s://rook-ceph/vault:8200).

    namespace
        Namespace for the init Secret (default: rook-ceph).

    secret_name
        Name of the Kubernetes Secret holding the init material (default: vault-init).

    kms_unseal
        Vault uses a KMS auto-unseal seal such as Azure Key Vault (default: True).
        When True, secret_shares/secret_threshold are not sent (not accepted by
        KMS seal types); recovery_shares/recovery_threshold are used instead.

    key_shares
        Number of key shares / recovery shares (default: 5).

    key_threshold
        Key / recovery threshold (default: 3).

    verify
        Verify TLS certificates (default: False).

    Example:
    .. code-block:: yaml

        vault_initialized:
          vault.initialized:
            - name: vault-init
            - vault_addr: k8s://rook-ceph/vault:8200
            - namespace: rook-ceph
            - secret_name: vault-init
            - kms_unseal: true
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_vault.initialize"](
            vault_addr=vault_addr,
            namespace=namespace,
            secret_name=secret_name,
            kms_unseal=kms_unseal,
            key_shares=key_shares,
            key_threshold=key_threshold,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to initialize Vault {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def auth_method_present(
    name,
    method="kubernetes",
    path=None,
    description="",
    vault_addr="k8s://rook-ceph/vault:8200",
    token=None,
    namespace="rook-ceph",
    secret_name="vault-init",
    verify=False,
):
    """
    Ensure a Vault auth method is enabled.

    name
        The name of the state.

    method
        Auth method type (default: kubernetes).

    path
        Mount path for the auth method (default: same as method).

    description
        Description for the auth method.

    Example:
    .. code-block:: yaml

        vault_kubernetes_auth:
          vault.auth_method_present:
            - name: kubernetes-auth
            - method: kubernetes
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_vault.auth_method_present"](
            method=method,
            path=path,
            description=description,
            vault_addr=vault_addr,
            token=token,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure auth method {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def kubernetes_auth_configured(
    name,
    sa_secret_name,
    sa_namespace="rook-ceph",
    kubernetes_host=None,
    issuer=None,
    mount="kubernetes",
    vault_addr="k8s://rook-ceph/vault:8200",
    token=None,
    namespace="rook-ceph",
    secret_name="vault-init",
    verify=False,
):
    """
    Ensure the Vault kubernetes auth method is configured.

    name
        The name of the state.

    sa_secret_name
        Name of the ServiceAccount token Secret (keys: token, ca.crt).

    sa_namespace
        Namespace of the ServiceAccount Secret (default: rook-ceph).

    kubernetes_host
        Kubernetes API address
        (default: https://kubernetes.default.svc.cluster.local).

    issuer
        Token issuer (default: https://kubernetes.default.svc.cluster.local).

    mount
        Auth mount path (default: kubernetes).

    Example:
    .. code-block:: yaml

        vault_kubernetes_auth_config:
          vault.kubernetes_auth_configured:
            - name: kubernetes-auth-config
            - sa_secret_name: vault-auth-token
            - sa_namespace: rook-ceph
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_vault.kubernetes_auth_configure"](
            kubernetes_host=kubernetes_host,
            sa_secret_name=sa_secret_name,
            sa_namespace=sa_namespace,
            issuer=issuer,
            mount=mount,
            vault_addr=vault_addr,
            token=token,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to configure kubernetes auth {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def secrets_engine_present(
    name,
    path=None,
    engine_type="kv",
    options=None,
    vault_addr="k8s://rook-ceph/vault:8200",
    token=None,
    namespace="rook-ceph",
    secret_name="vault-init",
    verify=False,
):
    """
    Ensure a Vault secrets engine is mounted.

    name
        The name of the state. Used as the mount path if path is not set.

    path
        Mount path for the secrets engine (default: name).

    engine_type
        Secrets engine type (default: kv).

    options
        Engine options (default: version 2 when engine_type is kv).

    Example:
    .. code-block:: yaml

        vault_rook_engine:
          vault.secrets_engine_present:
            - name: rook
            - engine_type: kv
    """
    ret = _state_ret(name)

    if path is None:
        path = name

    try:
        result = __salt__["kinetic_vault.secrets_engine_present"](
            path=path,
            engine_type=engine_type,
            options=options,
            vault_addr=vault_addr,
            token=token,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure secrets engine {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def policy_present(
    name,
    policy=None,
    policy_pillar=None,
    vault_addr="k8s://rook-ceph/vault:8200",
    token=None,
    namespace="rook-ceph",
    secret_name="vault-init",
    verify=False,
):
    """
    Ensure a Vault ACL policy exists with the given content.

    name
        The name of the policy.

    policy
        Policy document (HCL) as a string.

    policy_pillar
        Pillar key containing the policy document. Used when policy
        is not given directly.

    Example:
    .. code-block:: yaml

        vault_rook_policy:
          vault.policy_present:
            - name: rook
            - policy_pillar: 'vault:policies:rook'
    """
    ret = _state_ret(name)

    try:
        if policy_pillar and policy is None:
            policy = __salt__["pillar.get"](policy_pillar, "")

        if not policy:
            ret["result"] = False
            ret["comment"] = (
                f"No policy content provided for {name}; set policy or "
                f"policy_pillar to a non-empty value"
            )
            return ret

        result = __salt__["kinetic_vault.policy_present"](
            name=name,
            policy=policy,
            vault_addr=vault_addr,
            token=token,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure policy {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def kubernetes_role_present(
    name,
    bound_service_account_names,
    bound_service_account_namespaces,
    policies,
    ttl="1440h",
    audience="https://kubernetes.default.svc.cluster.local",
    mount="kubernetes",
    role_name=None,
    vault_addr="k8s://rook-ceph/vault:8200",
    token=None,
    namespace="rook-ceph",
    secret_name="vault-init",
    verify=False,
):
    """
    Ensure a Vault kubernetes auth role exists.

    name
        The name of the state. Used as the role name if role_name
        is not set.

    bound_service_account_names
        ServiceAccount names (list or comma-separated string).

    bound_service_account_namespaces
        ServiceAccount namespaces (list or comma-separated string).

    policies
        Policies to attach (list or comma-separated string).

    ttl
        Token TTL (default: 1440h).

    audience
        Token audience (default: https://kubernetes.default.svc.cluster.local).

    mount
        Auth mount path (default: kubernetes).

    role_name
        Role name (default: name).

    Example:
    .. code-block:: yaml

        vault_rook_role:
          vault.kubernetes_role_present:
            - name: rook-ceph-osd
            - bound_service_account_names:
                - rook-ceph-osd
            - bound_service_account_namespaces:
                - rook-ceph
            - policies:
                - rook
            - ttl: 1440h
    """
    ret = _state_ret(name)

    if role_name is None:
        role_name = name

    try:
        result = __salt__["kinetic_vault.kubernetes_role_present"](
            role_name=role_name,
            bound_service_account_names=bound_service_account_names,
            bound_service_account_namespaces=bound_service_account_namespaces,
            policies=policies,
            ttl=ttl,
            audience=audience,
            mount=mount,
            vault_addr=vault_addr,
            token=token,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure kubernetes role {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def approle_present(
    name,
    token_policies,
    token_ttl="1h",
    token_max_ttl="4h",
    mount="approle",
    role_name=None,
    vault_addr="k8s://rook-ceph/vault:8200",
    token=None,
    namespace="rook-ceph",
    secret_name="vault-init",
    verify=False,
):
    """
    Ensure a Vault AppRole exists with the given token policies.

    name
        The name of the state. Used as the role name if role_name
        is not set.

    token_policies
        Policies for issued tokens (list or comma-separated string).

    token_ttl
        Token TTL (default: 1h).

    token_max_ttl
        Token max TTL (default: 4h).

    mount
        Auth mount path (default: approle).

    role_name
        AppRole name (default: name).

    Example:
    .. code-block:: yaml

        vault_rook_approle:
          vault.approle_present:
            - name: rook
            - token_policies:
                - rook
            - token_ttl: 1h
            - token_max_ttl: 4h
    """
    ret = _state_ret(name)

    if role_name is None:
        role_name = name

    try:
        result = __salt__["kinetic_vault.approle_present"](
            role_name=role_name,
            token_policies=token_policies,
            token_ttl=token_ttl,
            token_max_ttl=token_max_ttl,
            mount=mount,
            vault_addr=vault_addr,
            token=token,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure AppRole {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def approle_secret_present(
    name,
    role_name,
    k8s_secret_name=None,
    k8s_namespace="rook-ceph",
    regenerate=False,
    mount="approle",
    vault_addr="k8s://rook-ceph/vault:8200",
    token=None,
    namespace="rook-ceph",
    secret_name="vault-init",
    verify=False,
):
    """
    Ensure AppRole credentials are stored in a Kubernetes Secret.

    name
        The name of the state. Used as the Kubernetes Secret name if
        k8s_secret_name is not set.

    role_name
        Name of the AppRole to fetch credentials for.

    k8s_secret_name
        Name of the Kubernetes Secret to store credentials in (default: name).

    k8s_namespace
        Namespace for the Kubernetes Secret (default: rook-ceph).

    regenerate
        Regenerate credentials even if the Secret exists (default: False).

    mount
        Auth mount path (default: approle).

    Example:
    .. code-block:: yaml

        vault_rook_approle_secret:
          vault.approle_secret_present:
            - name: rook-vault-approle
            - role_name: rook
            - k8s_namespace: rook-ceph
    """
    ret = _state_ret(name)

    if k8s_secret_name is None:
        k8s_secret_name = name

    try:
        result = __salt__["kinetic_vault.approle_credentials_to_secret"](
            role_name=role_name,
            k8s_secret_name=k8s_secret_name,
            k8s_namespace=k8s_namespace,
            mount=mount,
            regenerate=regenerate,
            vault_addr=vault_addr,
            token=token,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure AppRole secret {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret
