# -*- coding: utf-8 -*-
"""
SaltStack state module for Keycloak management.

This module provides states to manage Keycloak via the kinetic_keycloak
execution module (Keycloak Admin REST API). It is distinct from the
k8s.keycloak_cluster_present state, which manages the Keycloak Operator
Custom Resource.
"""

def __virtual__():
    """
    Only load if the kinetic_keycloak execution module is available.
    """
    if "kinetic_keycloak.get_admin_token" in __salt__:
        return "keycloak"
    return (
        False,
        "kinetic_keycloak execution module not available"
    )


def _state_ret(name):
    """Return a standard SaltStack state return dict."""
    return {"name": name, "result": False, "comment": "", "changes": {}}


def realm_present(
    name,
    enabled=True,
    password_policy=None,
    brute_force_protected=None,
    failure_factor=None,
    wait_increment_seconds=None,
    max_failure_wait_seconds=None,
    max_delta_time_seconds=None,
    quick_login_check_milli_seconds=None,
    minimum_quick_login_wait_seconds=None,
    access_token_lifespan=None,
    sso_session_idle_timeout=None,
    sso_session_max_lifespan=None,
    client_session_idle_timeout=None,
    client_session_max_lifespan=None,
    offline_session_idle_timeout=None,
    ssl_required=None,
    remember_me=None,
    verify_email=None,
    login_with_email_allowed=None,
    duplicate_emails_allowed=None,
    reset_password_allowed=None,
    edit_username_allowed=None,
    registration_allowed=None,
    registration_email_as_username=None,
    login_theme=None,
    account_theme=None,
    admin_theme=None,
    email_theme=None,
    smtp_server=None,
    browser_flow=None,
    registration_flow=None,
    direct_grant_flow=None,
    reset_credentials_flow=None,
    client_authentication_flow=None,
    docker_authentication_flow=None,
    attributes=None,
    spec=None,
    keycloak_addr="k8s://keycloak/keycloak-service:8443",
    token=None,
    realm_username=None,
    realm_password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Ensure a Keycloak realm exists with the given settings.

    name
        The name of the realm.

    enabled
        Whether the realm is enabled (default: True).

    browser_flow
        Alias of the authentication flow to bind as this realm's browser
        login flow (maps to browserFlow). Also see registration_flow,
        direct_grant_flow, reset_credentials_flow, client_authentication_flow,
        and docker_authentication_flow for the other flow bindings.

    spec
        Full realm representation fields to merge over (and override) the
        fields built from the other arguments.

    Example:
    .. code-block:: yaml

        my_realm:
          keycloak.realm_present:
            - name: myrealm
            - enabled: true
            - login_theme: keycloak
            - sso_session_idle_timeout: 1800
            - brute_force_protected: true
            - browser_flow: "browser with otp"
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_keycloak.realm_present"](
            name=name,
            enabled=enabled,
            password_policy=password_policy,
            brute_force_protected=brute_force_protected,
            failure_factor=failure_factor,
            wait_increment_seconds=wait_increment_seconds,
            max_failure_wait_seconds=max_failure_wait_seconds,
            max_delta_time_seconds=max_delta_time_seconds,
            quick_login_check_milli_seconds=quick_login_check_milli_seconds,
            minimum_quick_login_wait_seconds=minimum_quick_login_wait_seconds,
            access_token_lifespan=access_token_lifespan,
            sso_session_idle_timeout=sso_session_idle_timeout,
            sso_session_max_lifespan=sso_session_max_lifespan,
            client_session_idle_timeout=client_session_idle_timeout,
            client_session_max_lifespan=client_session_max_lifespan,
            offline_session_idle_timeout=offline_session_idle_timeout,
            ssl_required=ssl_required,
            remember_me=remember_me,
            verify_email=verify_email,
            login_with_email_allowed=login_with_email_allowed,
            duplicate_emails_allowed=duplicate_emails_allowed,
            reset_password_allowed=reset_password_allowed,
            edit_username_allowed=edit_username_allowed,
            registration_allowed=registration_allowed,
            registration_email_as_username=registration_email_as_username,
            login_theme=login_theme,
            account_theme=account_theme,
            admin_theme=admin_theme,
            email_theme=email_theme,
            smtp_server=smtp_server,
            browser_flow=browser_flow,
            registration_flow=registration_flow,
            direct_grant_flow=direct_grant_flow,
            reset_credentials_flow=reset_credentials_flow,
            client_authentication_flow=client_authentication_flow,
            docker_authentication_flow=docker_authentication_flow,
            attributes=attributes,
            spec=spec,
            keycloak_addr=keycloak_addr,
            token=token,
            realm_username=realm_username,
            realm_password=realm_password,
            admin_client_id=admin_client_id,
            admin_client_secret=admin_client_secret,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure realm {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def realm_absent(
    name,
    keycloak_addr="k8s://keycloak/keycloak-service:8443",
    token=None,
    realm_username=None,
    realm_password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Ensure a Keycloak realm does not exist.

    name
        The name of the realm.

    Example:
    .. code-block:: yaml

        my_realm_absent:
          keycloak.realm_absent:
            - name: myrealm
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_keycloak.realm_absent"](
            name=name,
            keycloak_addr=keycloak_addr,
            token=token,
            realm_username=realm_username,
            realm_password=realm_password,
            admin_client_id=admin_client_id,
            admin_client_secret=admin_client_secret,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to delete realm {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def events_config_present(
    name,
    events_enabled=None,
    events_listeners=None,
    enabled_event_types=None,
    events_expiration=None,
    admin_events_enabled=None,
    admin_events_details_enabled=None,
    spec=None,
    keycloak_addr="k8s://keycloak/keycloak-service:8443",
    token=None,
    realm_username=None,
    realm_password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Ensure realm events (login/admin event logging) configuration matches
    the desired settings.

    name
        The name of the realm.

    Example:
    .. code-block:: yaml

        my_realm_events:
          keycloak.events_config_present:
            - name: myrealm
            - events_enabled: true
            - admin_events_enabled: true
            - admin_events_details_enabled: true
            - events_expiration: 604800
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_keycloak.events_config_present"](
            realm=name,
            events_enabled=events_enabled,
            events_listeners=events_listeners,
            enabled_event_types=enabled_event_types,
            events_expiration=events_expiration,
            admin_events_enabled=admin_events_enabled,
            admin_events_details_enabled=admin_events_details_enabled,
            spec=spec,
            keycloak_addr=keycloak_addr,
            token=token,
            realm_username=realm_username,
            realm_password=realm_password,
            admin_client_id=admin_client_id,
            admin_client_secret=admin_client_secret,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure events config for realm {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def required_action_present(
    name,
    realm,
    provider_id,
    alias=None,
    display_name=None,
    enabled=True,
    default_action=False,
    priority=None,
    config=None,
    keycloak_addr="k8s://keycloak/keycloak-service:8443",
    token=None,
    realm_username=None,
    realm_password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Ensure a realm required action is registered and configured.

    name
        The name of the state (informational only).

    realm
        The realm to configure the required action in.

    provider_id
        Required action provider id (e.g. CONFIGURE_TOTP).

    alias
        Required action alias (default: provider_id).

    display_name
        Display name used only at registration time (default: provider_id).

    Example:
    .. code-block:: yaml

        totp_required_action:
          keycloak.required_action_present:
            - name: totp
            - realm: myrealm
            - provider_id: CONFIGURE_TOTP
            - enabled: true
            - default_action: false
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_keycloak.required_action_present"](
            realm=realm,
            provider_id=provider_id,
            alias=alias,
            name=display_name,
            enabled=enabled,
            default_action=default_action,
            priority=priority,
            config=config,
            keycloak_addr=keycloak_addr,
            token=token,
            realm_username=realm_username,
            realm_password=realm_password,
            admin_client_id=admin_client_id,
            admin_client_secret=admin_client_secret,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure required action {provider_id}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def authentication_flow_present(
    name,
    realm,
    alias=None,
    description=None,
    provider_id="basic-flow",
    top_level=True,
    built_in=False,
    keycloak_addr="k8s://keycloak/keycloak-service:8443",
    token=None,
    realm_username=None,
    realm_password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Ensure an authentication flow exists.

    name
        The name of the state. Used as the flow alias if alias is not set.

    realm
        The realm to create the flow in.

    alias
        Flow alias (default: name).

    Example:
    .. code-block:: yaml

        my_browser_flow:
          keycloak.authentication_flow_present:
            - realm: myrealm
            - description: Custom browser flow with OTP
            - provider_id: basic-flow
            - top_level: true
    """
    ret = _state_ret(name)

    if alias is None:
        alias = name

    try:
        result = __salt__["kinetic_keycloak.authentication_flow_present"](
            realm=realm,
            alias=alias,
            description=description,
            provider_id=provider_id,
            top_level=top_level,
            built_in=built_in,
            keycloak_addr=keycloak_addr,
            token=token,
            realm_username=realm_username,
            realm_password=realm_password,
            admin_client_id=admin_client_id,
            admin_client_secret=admin_client_secret,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure authentication flow {alias}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def authentication_flow_absent(
    name,
    realm,
    alias=None,
    keycloak_addr="k8s://keycloak/keycloak-service:8443",
    token=None,
    realm_username=None,
    realm_password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Ensure an authentication flow does not exist.

    name
        The name of the state. Used as the flow alias if alias is not set.

    realm
        The realm the flow belongs to.

    alias
        Flow alias (default: name).

    Example:
    .. code-block:: yaml

        my_browser_flow_absent:
          keycloak.authentication_flow_absent:
            - realm: myrealm
    """
    ret = _state_ret(name)

    if alias is None:
        alias = name

    try:
        result = __salt__["kinetic_keycloak.authentication_flow_absent"](
            realm=realm,
            alias=alias,
            keycloak_addr=keycloak_addr,
            token=token,
            realm_username=realm_username,
            realm_password=realm_password,
            admin_client_id=admin_client_id,
            admin_client_secret=admin_client_secret,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to delete authentication flow {alias}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def authentication_execution_present(
    name,
    realm,
    flow_alias,
    provider_id,
    requirement="DISABLED",
    type="execution",          # "execution" or "flow"
    keycloak_addr="k8s://keycloak/keycloak-service:8443",
    token=None,
    realm_username=None,
    realm_password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Ensure an authentication execution exists within a flow with the given
    requirement. Execution priority/ordering is not managed by this state.

    name
        The name of the state (informational only).

    realm
        The realm the flow belongs to.

    flow_alias
        Alias of the flow to add/update the execution in.

    provider_id
        Execution provider id (or sub-flow alias when type="flow").

    type
        "execution" (default) or "flow" (to register a sub-flow).

    Example:
    .. code-block:: yaml

        otp_execution:
          keycloak.authentication_execution_present:
            - name: otp-in-browser-flow
            - realm: myrealm
            - flow_alias: my-browser-flow
            - provider_id: auth-otp-form
            - requirement: REQUIRED
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_keycloak.authentication_execution_present"](
            realm=realm,
            flow_alias=flow_alias,
            provider_id=provider_id,
            requirement=requirement,
            type=type,
            keycloak_addr=keycloak_addr,
            token=token,
            realm_username=realm_username,
            realm_password=realm_password,
            admin_client_id=admin_client_id,
            admin_client_secret=admin_client_secret,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = (
            f"Failed to ensure execution {provider_id} in flow {flow_alias}: "
            f"{str(e)[:100]}..."
        )
        ret["changes"] = {}

    return ret


def client_present(
    name,
    realm,
    client_id=None,
    client_name=None,
    description=None,
    enabled=True,
    protocol="openid-connect",
    public_client=False,
    standard_flow_enabled=True,
    direct_access_grants_enabled=True,
    service_accounts_enabled=False,
    authorization_services_enabled=False,
    redirect_uris=None,
    web_origins=None,
    root_url=None,
    base_url=None,
    client_authenticator_type="client-secret",
    secret=None,
    pkce_code_challenge_method=None,
    attributes=None,
    spec=None,
    keycloak_addr="k8s://keycloak/keycloak-service:8443",
    token=None,
    realm_username=None,
    realm_password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Ensure a Keycloak client exists in the given realm.

    name
        The name of the state. Used as the Keycloak clientId if client_id
        is not set.

    realm
        The realm to create the client in.

    client_id
        Keycloak clientId of the client to manage (default: name).

    client_name
        Display name for the client (Keycloak's "name" field).

    pkce_code_challenge_method
        PKCE code challenge method (e.g. S256, plain). Defaults to "S256"
        when public_client is true, unless explicitly set here or in
        attributes/spec. Pass an empty string to explicitly disable PKCE
        enforcement for a public client.

    attributes
        Free-form client attributes to merge into (not replace) the
        client's existing attributes map.

    Example:
    .. code-block:: yaml

        my_app_client:
          keycloak.client_present:
            - name: my-app
            - realm: myrealm
            - client_name: My Application
            - redirect_uris:
                - https://app.example.com/*
            - web_origins:
                - https://app.example.com
            - public_client: false
            - standard_flow_enabled: true
            - direct_access_grants_enabled: false

        my_spa_client:
          keycloak.client_present:
            - name: my-spa
            - realm: myrealm
            - client_name: My SPA
            - public_client: true
            - redirect_uris:
                - https://spa.example.com/*
            # pkce.code.challenge.method defaults to S256 automatically
            # for public clients; no need to set it explicitly.
    """
    ret = _state_ret(name)

    if client_id is None:
        client_id = name

    try:
        result = __salt__["kinetic_keycloak.client_present"](
            realm=realm,
            client_id=client_id,
            name=client_name,
            description=description,
            enabled=enabled,
            protocol=protocol,
            public_client=public_client,
            standard_flow_enabled=standard_flow_enabled,
            direct_access_grants_enabled=direct_access_grants_enabled,
            service_accounts_enabled=service_accounts_enabled,
            authorization_services_enabled=authorization_services_enabled,
            redirect_uris=redirect_uris,
            web_origins=web_origins,
            root_url=root_url,
            base_url=base_url,
            client_authenticator_type=client_authenticator_type,
            secret=secret,
            pkce_code_challenge_method=pkce_code_challenge_method,
            attributes=attributes,
            spec=spec,
            keycloak_addr=keycloak_addr,
            token=token,
            realm_username=realm_username,
            realm_password=realm_password,
            admin_client_id=admin_client_id,
            admin_client_secret=admin_client_secret,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure client {client_id}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def client_default_scope_present(
    name,
    realm,
    scope_name,
    client_id=None,
    keycloak_addr="k8s://keycloak/keycloak-service:8443",
    token=None,
    realm_username=None,
    realm_password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Ensure a client scope is assigned to a client as a DEFAULT client scope.

    This is additive/idempotent - it does not remove any other default or
    optional client scopes already assigned to the client.

    name
        The name of the state. Used as the Keycloak clientId if client_id
        is not set.

    realm
        The realm the client belongs to.

    scope_name
        Name of the client scope to assign as default (e.g. "groups").
        Must already exist in the realm.

    client_id
        Keycloak clientId of the client to manage (default: name).

    Example:
    .. code-block:: yaml

        my_app_groups_scope:
          keycloak.client_default_scope_present:
            - name: my-app
            - realm: myrealm
            - scope_name: groups
    """
    ret = _state_ret(name)

    if client_id is None:
        client_id = name

    try:
        result = __salt__["kinetic_keycloak.client_default_scope_present"](
            realm=realm,
            client_id=client_id,
            scope_name=scope_name,
            keycloak_addr=keycloak_addr,
            token=token,
            realm_username=realm_username,
            realm_password=realm_password,
            admin_client_id=admin_client_id,
            admin_client_secret=admin_client_secret,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure default client scope {scope_name} on client {client_id}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def client_absent(
    name,
    realm,
    client_id=None,
    keycloak_addr="k8s://keycloak/keycloak-service:8443",
    token=None,
    realm_username=None,
    realm_password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Ensure a Keycloak client does not exist in the given realm.

    name
        The name of the state. Used as the Keycloak clientId if client_id
        is not set.

    realm
        The realm the client belongs to.

    client_id
        Keycloak clientId of the client to remove (default: name).

    Example:
    .. code-block:: yaml

        my_app_client_absent:
          keycloak.client_absent:
            - name: my-app
            - realm: myrealm
    """
    ret = _state_ret(name)

    if client_id is None:
        client_id = name

    try:
        result = __salt__["kinetic_keycloak.client_absent"](
            realm=realm,
            client_id=client_id,
            keycloak_addr=keycloak_addr,
            token=token,
            realm_username=realm_username,
            realm_password=realm_password,
            admin_client_id=admin_client_id,
            admin_client_secret=admin_client_secret,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to delete client {client_id}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def user_federation_present(
    name,
    realm,
    provider_id="ldap",
    provider_type="org.keycloak.storage.UserStorageProvider",
    parent_id=None,
    start_tls=None,
    use_truststore_spi=None,
    config=None,
    keycloak_addr="k8s://keycloak/keycloak-service:8443",
    token=None,
    realm_username=None,
    realm_password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Ensure a realm-level user storage federation provider (e.g. LDAP) exists.

    name
        The name of the state. Also used as the Keycloak component name.

    realm
        The realm to create the federation provider in.

    start_tls
        Use StartTLS to negotiate encryption on the plain LDAP port
        (config key startTls). Ignored if config already sets startTls.

    use_truststore_spi
        When to use Keycloak's truststore SPI for LDAP connections
        (config key useTruststoreSpi): one of "always", "ldapsOnly", or
        "never". Ignored if config already sets useTruststoreSpi.

    Example:
    .. code-block:: yaml

        corp_ldap:
          keycloak.user_federation_present:
            - name: corp-ldap
            - realm: myrealm
            - provider_id: ldap
            - start_tls: true
            - use_truststore_spi: ldapsOnly
            - config:
                connectionUrl: ldap://ldap.example.com:389
                usersDn: ou=People,dc=example,dc=com
                bindDn: cn=admin,dc=example,dc=com
                bindCredential: {{ pillar['ldap']['bind_password'] }}
                userObjectClasses: "inetOrgPerson, organizationalPerson"
                vendor: other
                editMode: READ_ONLY
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_keycloak.user_federation_present"](
            realm=realm,
            name=name,
            provider_id=provider_id,
            provider_type=provider_type,
            parent_id=parent_id,
            start_tls=start_tls,
            use_truststore_spi=use_truststore_spi,
            config=config,
            keycloak_addr=keycloak_addr,
            token=token,
            realm_username=realm_username,
            realm_password=realm_password,
            admin_client_id=admin_client_id,
            admin_client_secret=admin_client_secret,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure user federation provider {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def user_federation_absent(
    name,
    realm,
    provider_type="org.keycloak.storage.UserStorageProvider",
    keycloak_addr="k8s://keycloak/keycloak-service:8443",
    token=None,
    realm_username=None,
    realm_password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Ensure a realm-level user storage federation provider does not exist.

    name
        The name of the state. Also used as the Keycloak component name.

    realm
        The realm the federation provider belongs to.

    Example:
    .. code-block:: yaml

        corp_ldap_absent:
          keycloak.user_federation_absent:
            - name: corp-ldap
            - realm: myrealm
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_keycloak.user_federation_absent"](
            realm=realm,
            name=name,
            provider_type=provider_type,
            keycloak_addr=keycloak_addr,
            token=token,
            realm_username=realm_username,
            realm_password=realm_password,
            admin_client_id=admin_client_id,
            admin_client_secret=admin_client_secret,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to delete user federation provider {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def ldap_mapper_present(
    name,
    realm,
    federation_name,
    provider_id,
    config=None,
    provider_type="org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
    keycloak_addr="k8s://keycloak/keycloak-service:8443",
    token=None,
    realm_username=None,
    realm_password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Ensure an LDAP mapper component (e.g. group-ldap-mapper,
    user-attribute-ldap-mapper, full-name-ldap-mapper,
    hardcoded-ldap-role-mapper, msad-user-account-control-mapper) exists
    under a given realm-level user storage federation provider (e.g. LDAP).

    name
        The name of the state. Also used as the Keycloak mapper component
        name.

    realm
        The realm the federation provider belongs to.

    federation_name
        Name of the parent user federation provider component (as set via
        keycloak.user_federation_present's name).

    provider_id
        Mapper provider id (e.g. group-ldap-mapper).

    Example:
    .. code-block:: yaml

        corp_ldap_groups_mapper:
          keycloak.ldap_mapper_present:
            - name: corp-ldap-groups
            - realm: myrealm
            - federation_name: corp-ldap
            - provider_id: group-ldap-mapper
            - config:
                groups.dn: ou=groups,dc=example,dc=com
                group.name.ldap.attribute: cn
                group.object.classes: groupOfNames
                membership.ldap.attribute: member
                membership.attribute.type: DN
                membership.user.ldap.attribute: uid
                mode: READ_ONLY
                user.roles.retrieve.strategy: LOAD_GROUPS_BY_MEMBER_ATTRIBUTE
                mapped.group.attributes: ""
                drop.non.existing.groups.during.sync: "false"
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_keycloak.ldap_mapper_present"](
            realm=realm,
            federation_name=federation_name,
            name=name,
            provider_id=provider_id,
            config=config,
            provider_type=provider_type,
            keycloak_addr=keycloak_addr,
            token=token,
            realm_username=realm_username,
            realm_password=realm_password,
            admin_client_id=admin_client_id,
            admin_client_secret=admin_client_secret,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to ensure LDAP mapper {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret


def ldap_mapper_absent(
    name,
    realm,
    federation_name,
    provider_type="org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
    keycloak_addr="k8s://keycloak/keycloak-service:8443",
    token=None,
    realm_username=None,
    realm_password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Ensure an LDAP mapper component does not exist under a given
    realm-level user storage federation provider (e.g. LDAP).

    name
        The name of the state. Also used as the Keycloak mapper component
        name.

    realm
        The realm the federation provider belongs to.

    federation_name
        Name of the parent user federation provider component (as set via
        keycloak.user_federation_present's name).

    Example:
    .. code-block:: yaml

        corp_ldap_groups_mapper_absent:
          keycloak.ldap_mapper_absent:
            - name: corp-ldap-groups
            - realm: myrealm
            - federation_name: corp-ldap
    """
    ret = _state_ret(name)

    try:
        result = __salt__["kinetic_keycloak.ldap_mapper_absent"](
            realm=realm,
            federation_name=federation_name,
            name=name,
            provider_type=provider_type,
            keycloak_addr=keycloak_addr,
            token=token,
            realm_username=realm_username,
            realm_password=realm_password,
            admin_client_id=admin_client_id,
            admin_client_secret=admin_client_secret,
            namespace=namespace,
            secret_name=secret_name,
            verify=verify,
        )

        ret["result"] = result.get("success", False)
        ret["comment"] = result.get("message", "Unknown error")
        ret["changes"] = {"updated": True} if result.get("updated", False) else {}

    except Exception as e:
        ret["result"] = False
        ret["comment"] = f"Failed to delete LDAP mapper {name}: {str(e)[:100]}..."
        ret["changes"] = {}

    return ret
