# -*- coding: utf-8 -*-
"""
SaltStack execution module for Keycloak management.

This module manages Keycloak via its Admin REST API
(https://www.keycloak.org/docs-api/latest/rest-api/index.html), not via
kubectl exec and not via the Keycloak Operator Custom Resource (that is
handled separately by k8s.keycloak_cluster_present). It follows the dual
transport / token-lookup / idempotency pattern established in
kinetic-vault.py.
"""

import base64
import json
import logging
from urllib.parse import urlencode

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

__virtualname__ = "kinetic_keycloak"

# Default transport routes through the Kubernetes API server service proxy,
# so the Keycloak Admin API does not need to be exposed outside the cluster.
# Format: k8s://<namespace>/<service>:<port>
# A regular https:// address is also supported for direct access.
DEFAULT_KEYCLOAK_ADDR = "k8s://keycloak/keycloak-service:8443"


@decorators.memoize
def __virtual__():
    """
    Check if the requests and kubernetes python libraries are available.
    """
    if HAS_LIBS:
        return "kinetic_keycloak"
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


def _request_via_k8s_proxy(method, addr, path, headers=None, payload=None, form_data=None):
    """
    Make an HTTP request against the Keycloak Admin API through the
    Kubernetes API server service proxy. This works even when the Keycloak
    API is not exposed outside the cluster; only Kubernetes API access is
    required.

    addr format: k8s://<namespace>/<service>:<port>
    path is the full Keycloak API path (e.g. "admin/realms/myrealm" or
    "realms/master/protocol/openid-connect/token"), without a leading slash.

    Supports both JSON payloads (payload=dict) and form-encoded payloads
    (form_data=dict, used by the OpenID Connect token endpoint).

    Returns:
        tuple: (status_code, body) where body is a parsed JSON value, a raw
            decoded string (for non-JSON responses), or None (empty body).
    """
    _load_k8s_config()

    # Parse k8s://<namespace>/<service>:<port>
    stripped = addr[len("k8s://"):]
    svc_namespace, service_port = stripped.split("/", 1)

    api_client = client.ApiClient()
    proxy_path = (
        f"/api/v1/namespaces/{svc_namespace}/services/"
        f"https:{service_port}/proxy/{path}"
    )

    header_params = {"Accept": "application/json"}
    body = None
    if form_data is not None:
        header_params["Content-Type"] = "application/x-www-form-urlencoded"
        body = urlencode(form_data)
    elif payload is not None:
        header_params["Content-Type"] = "application/json"
        body = payload

    if headers:
        header_params.update(headers)

    try:
        resp = api_client.call_api(
            proxy_path,
            method.upper(),
            header_params=header_params,
            body=body,
            auth_settings=["BearerToken"],
            _preload_content=False,
            _return_http_data_only=True,
            _request_timeout=15,
        )
        status_code = resp.status
        raw = resp.data
    except ApiException as e:
        # Keycloak intentionally returns non-2xx codes for various states
        # (404 for missing realms/clients, etc.); the kubernetes client
        # raises for those, so unwrap the response.
        status_code = e.status
        raw = e.body

    if isinstance(raw, bytes):
        raw = raw.decode("utf-8")

    body_out = None
    if raw:
        try:
            body_out = json.loads(raw)
        except (ValueError, TypeError):
            body_out = raw
    return status_code, body_out


def _request(method, addr, path, headers=None, payload=None, form_data=None, verify=False):
    """
    Make an HTTP request against the Keycloak Admin API.

    Supports two transports based on the addr scheme:
    - k8s://<namespace>/<service>:<port>  -> Kubernetes API server service proxy
      (use when the Keycloak API is not exposed outside the cluster)
    - https://host:port                    -> direct HTTPS

    Returns:
        tuple: (status_code, body) where body is a parsed JSON value, a raw
            decoded string (for non-JSON responses), or None (empty body).
    """
    if addr.startswith("k8s://"):
        return _request_via_k8s_proxy(
            method, addr, path, headers=headers, payload=payload, form_data=form_data
        )

    url = f"{addr}/{path}"
    request_kwargs = {
        "headers": dict(headers) if headers else {},
        "verify": verify,
        "timeout": 15,
    }
    if form_data is not None:
        request_kwargs["data"] = form_data
    else:
        request_kwargs["json"] = payload

    resp = requests.request(method, url, **request_kwargs)

    body_out = None
    if resp.content:
        try:
            body_out = resp.json()
        except ValueError:
            body_out = resp.text
    return resp.status_code, body_out


def _http_error(action, status_code, body):
    """Build a standard failure return dict for an unexpected HTTP response."""
    if isinstance(body, dict):
        text = json.dumps(body)
    else:
        text = str(body) if body is not None else ""
    return {
        "success": False,
        "updated": False,
        "message": f"{action} failed with HTTP {status_code}: {text[:200]}",
    }


def _get_admin_credentials(namespace, secret_name):
    """
    Read Keycloak admin username/password from a Kubernetes Secret.

    Args:
        namespace (str): Namespace of the Secret.
        secret_name (str): Name of the Secret (keys: username, password).

    Returns:
        tuple: (username, password), or (None, None) if the Secret or the
            expected keys are not found.
    """
    try:
        _load_k8s_config()
        core_api = client.CoreV1Api()
        secret = core_api.read_namespaced_secret(secret_name, namespace)
        data = secret.data or {}
        username = base64.b64decode(data["username"]).decode("utf-8")
        password = base64.b64decode(data["password"]).decode("utf-8")
        return username, password
    except ApiException as e:
        if e.status == 404:
            return None, None
        raise
    except KeyError:
        return None, None


def get_admin_token(
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
    realm="master",
    username=None,
    password=None,
    admin_client_id="admin-cli",
    admin_client_secret=None,
    namespace="keycloak",
    secret_name="keycloak-admin",
    verify=False,
):
    """
    Obtain a Keycloak admin access token from the OpenID Connect token
    endpoint.

    Keycloak Admin REST API:
        POST realms/{realm}/protocol/openid-connect/token

    This enables dynamic runtime lookup from jinja:
    salt['kinetic_keycloak.get_admin_token']()

    If admin_client_secret is not given, this uses the resource owner
    password grant with username/password; if those are not both provided
    either, credentials are looked up from the Kubernetes Secret secret_name
    in namespace (keys: username, password).

    Args:
        keycloak_addr (str): Keycloak API address
            (default: k8s://keycloak/keycloak-service:8443)
        realm (str): Realm to authenticate against (default: master)
        username (str): Admin username
        password (str): Admin password
        admin_client_id (str): Client id used for the admin login
            (default: admin-cli)
        admin_client_secret (str): Client secret; when given, the client
            credentials grant is used instead of the password grant
        namespace (str): Namespace of the admin credentials Secret
            (default: keycloak)
        secret_name (str): Name of the admin credentials Secret
            (default: keycloak-admin)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        str: The access token, or None if it could not be obtained.
    """
    try:
        if admin_client_secret:
            form_data = {
                "grant_type": "client_credentials",
                "client_id": admin_client_id,
                "client_secret": admin_client_secret,
            }
        else:
            if not (username and password):
                username, password = _get_admin_credentials(namespace, secret_name)
            if not (username and password):
                log.error(
                    "Unable to obtain Keycloak admin credentials from secret %s/%s",
                    namespace, secret_name,
                )
                return None
            form_data = {
                "grant_type": "password",
                "client_id": admin_client_id,
                "username": username,
                "password": password,
            }

        status_code, body = _request(
            "POST",
            keycloak_addr,
            f"realms/{realm}/protocol/openid-connect/token",
            form_data=form_data,
            verify=verify,
        )
        if status_code == 200 and isinstance(body, dict):
            return body.get("access_token")

        log.error(
            "Failed to obtain Keycloak admin token (HTTP %s): %s", status_code, body
        )
        return None

    except Exception as e:
        log.error("Failed to obtain Keycloak admin token: %s", e)
        return None


def _auth_headers(token):
    """Build the Authorization/Accept headers for an authenticated request."""
    return {"Authorization": f"Bearer {token}", "Accept": "application/json"}


def _resolve_token(
    token,
    keycloak_addr,
    realm,
    username,
    password,
    admin_client_id,
    admin_client_secret,
    namespace,
    secret_name,
    verify,
):
    """Return the provided token, or obtain one via get_admin_token."""
    if token:
        return token
    return get_admin_token(
        keycloak_addr=keycloak_addr,
        realm=realm,
        username=username,
        password=password,
        admin_client_id=admin_client_id,
        admin_client_secret=admin_client_secret,
        namespace=namespace,
        secret_name=secret_name,
        verify=verify,
    )


def _to_component_config(config_dict):
    """
    Normalize a component config dict so every value is a List[str], as
    required by the Keycloak component representation (e.g. LDAP user
    federation config).
    """
    if not config_dict:
        return {}
    normalized = {}
    for key, value in config_dict.items():
        if isinstance(value, list):
            normalized[key] = [str(item) for item in value]
        else:
            normalized[key] = [str(value)]
    return normalized


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
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
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

    Keycloak Admin REST API:
        GET/POST admin/realms
        GET/PUT admin/realms/{realm}

    Args:
        name (str): Realm name (used as the realm id).
        enabled (bool): Whether the realm is enabled (default: True)
        password_policy (str): Password policy string
        brute_force_protected (bool): Enable brute force detection
        failure_factor (int): Number of failures before lockout
        wait_increment_seconds (int): Wait increment for lockout backoff
        max_failure_wait_seconds (int): Maximum lockout wait
        max_delta_time_seconds (int): Failure reset time
        quick_login_check_milli_seconds (int): Minimum time between login attempts
        minimum_quick_login_wait_seconds (int): Wait after a quick login failure
        access_token_lifespan (int): Access token lifespan in seconds
        sso_session_idle_timeout (int): SSO session idle timeout in seconds
        sso_session_max_lifespan (int): SSO session max lifespan in seconds
        client_session_idle_timeout (int): Client session idle timeout in seconds
        client_session_max_lifespan (int): Client session max lifespan in seconds
        offline_session_idle_timeout (int): Offline session idle timeout in seconds
        ssl_required (str): SSL requirement (none, external, all)
        remember_me (bool): Enable "remember me"
        verify_email (bool): Require email verification
        login_with_email_allowed (bool): Allow login with email
        duplicate_emails_allowed (bool): Allow duplicate emails
        reset_password_allowed (bool): Allow self-service password reset
        edit_username_allowed (bool): Allow users to edit their username
        registration_allowed (bool): Allow self-registration
        registration_email_as_username (bool): Use email as username on registration
        login_theme (str): Login theme name
        account_theme (str): Account console theme name
        admin_theme (str): Admin console theme name
        email_theme (str): Email theme name
        smtp_server (dict): SMTP server settings for email (maps to Keycloak's
            smtpServer realm field). Example:
            {
                "host": "smtp.example.com",
                "port": "587",
                "from": "keycloak@example.com",
                "fromDisplayName": "Keycloak",
                "auth": "true",
                "user": "username",
                "password": "secret",
                "starttls": "true",
                "ssl": "false"
            }
        browser_flow (str): Alias of the authentication flow to bind as this
            realm's browser login flow (maps to browserFlow)
        registration_flow (str): Alias of the flow to bind as the
            registration flow (maps to registrationFlow)
        direct_grant_flow (str): Alias of the flow to bind as the direct
            grant flow (maps to directGrantFlow)
        reset_credentials_flow (str): Alias of the flow to bind as the reset
            credentials flow (maps to resetCredentialsFlow)
        client_authentication_flow (str): Alias of the flow to bind as the
            client authentication flow (maps to clientAuthenticationFlow)
        docker_authentication_flow (str): Alias of the flow to bind as the
            docker authentication flow (maps to dockerAuthenticationFlow)
        attributes (dict): Free-form realm attributes
        spec (dict, optional): Full realm representation fields to merge over
            (and override) the fields built from the other kwargs
        keycloak_addr (str): Keycloak API address
            (default: k8s://keycloak/keycloak-service:8443)
        token (str): Bearer token; obtained via get_admin_token if not given
        realm_username (str): Admin username used to obtain a token
        realm_password (str): Admin password used to obtain a token
        admin_client_id (str): Client id used for the admin login (default: admin-cli)
        admin_client_secret (str): Client secret for confidential client login
        namespace (str): Namespace of the admin credentials Secret (default: keycloak)
        secret_name (str): Name of the admin credentials Secret (default: keycloak-admin)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message

    CLI Example:

        salt-call kinetic_keycloak.realm_present name=myrealm enabled=True
    """
    try:
        resolved_token = _resolve_token(
            token, keycloak_addr, "master", realm_username, realm_password,
            admin_client_id, admin_client_secret, namespace, secret_name, verify,
        )
        if not resolved_token:
            return {
                "success": False,
                "updated": False,
                "message": "Failed to obtain Keycloak admin access token",
            }
        headers = _auth_headers(resolved_token)

        field_map = {
            "password_policy": "passwordPolicy",
            "brute_force_protected": "bruteForceProtected",
            "failure_factor": "failureFactor",
            "wait_increment_seconds": "waitIncrementSeconds",
            "max_failure_wait_seconds": "maxFailureWaitSeconds",
            "max_delta_time_seconds": "maxDeltaTimeSeconds",
            "quick_login_check_milli_seconds": "quickLoginCheckMilliSeconds",
            "minimum_quick_login_wait_seconds": "minimumQuickLoginWaitSeconds",
            "access_token_lifespan": "accessTokenLifespan",
            "sso_session_idle_timeout": "ssoSessionIdleTimeout",
            "sso_session_max_lifespan": "ssoSessionMaxLifespan",
            "client_session_idle_timeout": "clientSessionIdleTimeout",
            "client_session_max_lifespan": "clientSessionMaxLifespan",
            "offline_session_idle_timeout": "offlineSessionIdleTimeout",
            "ssl_required": "sslRequired",
            "remember_me": "rememberMe",
            "verify_email": "verifyEmail",
            "login_with_email_allowed": "loginWithEmailAllowed",
            "duplicate_emails_allowed": "duplicateEmailsAllowed",
            "reset_password_allowed": "resetPasswordAllowed",
            "edit_username_allowed": "editUsernameAllowed",
            "registration_allowed": "registrationAllowed",
            "registration_email_as_username": "registrationEmailAsUsername",
            "login_theme": "loginTheme",
            "account_theme": "accountTheme",
            "admin_theme": "adminTheme",
            "email_theme": "emailTheme",
            "smtp_server": "smtpServer",
            "browser_flow": "browserFlow",
            "registration_flow": "registrationFlow",
            "direct_grant_flow": "directGrantFlow",
            "reset_credentials_flow": "resetCredentialsFlow",
            "client_authentication_flow": "clientAuthenticationFlow",
            "docker_authentication_flow": "dockerAuthenticationFlow",
            "attributes": "attributes",
        }
        local_vars = locals()
        desired = {
            camel: local_vars[snake]
            for snake, camel in field_map.items()
            if local_vars[snake] is not None
        }
        if spec:
            desired = {**desired, **spec}

        status_code, body = _request(
            "GET", keycloak_addr, f"admin/realms/{name}", headers=headers, verify=verify
        )

        if status_code == 404:
            payload = {"realm": name, "enabled": enabled, **desired}
            status_code, body = _request(
                "POST", keycloak_addr, "admin/realms",
                headers=headers, payload=payload, verify=verify,
            )
            if status_code in (201, 204):
                return {
                    "success": True,
                    "updated": True,
                    "message": f"Realm {name} created",
                }
            return _http_error(f"Creating realm {name}", status_code, body)

        elif status_code == 200 and isinstance(body, dict):
            matches = body.get("enabled") == enabled and all(
                body.get(k) == v for k, v in desired.items()
            )
            if matches:
                return {
                    "success": True,
                    "updated": False,
                    "message": f"Realm {name} already exists and matches desired state",
                }

            payload = {**body, "enabled": enabled, **desired}
            status_code, body = _request(
                "PUT", keycloak_addr, f"admin/realms/{name}",
                headers=headers, payload=payload, verify=verify,
            )
            if status_code == 204:
                return {
                    "success": True,
                    "updated": True,
                    "message": f"Realm {name} updated",
                }
            return _http_error(f"Updating realm {name}", status_code, body)

        return _http_error(f"Checking realm {name}", status_code, body)

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure realm {name}: {str(e)}",
        }


def realm_absent(
    name,
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
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

    Keycloak Admin REST API:
        GET/DELETE admin/realms/{realm}

    Args:
        name (str): Realm name.
        keycloak_addr (str): Keycloak API address
            (default: k8s://keycloak/keycloak-service:8443)
        token (str): Bearer token; obtained via get_admin_token if not given
        realm_username (str): Admin username used to obtain a token
        realm_password (str): Admin password used to obtain a token
        admin_client_id (str): Client id used for the admin login (default: admin-cli)
        admin_client_secret (str): Client secret for confidential client login
        namespace (str): Namespace of the admin credentials Secret (default: keycloak)
        secret_name (str): Name of the admin credentials Secret (default: keycloak-admin)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message

    CLI Example:

        salt-call kinetic_keycloak.realm_absent name=myrealm
    """
    try:
        resolved_token = _resolve_token(
            token, keycloak_addr, "master", realm_username, realm_password,
            admin_client_id, admin_client_secret, namespace, secret_name, verify,
        )
        if not resolved_token:
            return {
                "success": False,
                "updated": False,
                "message": "Failed to obtain Keycloak admin access token",
            }
        headers = _auth_headers(resolved_token)

        status_code, body = _request(
            "GET", keycloak_addr, f"admin/realms/{name}", headers=headers, verify=verify
        )
        if status_code == 404:
            return {
                "success": True,
                "updated": False,
                "message": f"Realm {name} already absent",
            }

        status_code, body = _request(
            "DELETE", keycloak_addr, f"admin/realms/{name}", headers=headers, verify=verify
        )
        if status_code == 204:
            return {
                "success": True,
                "updated": True,
                "message": f"Realm {name} deleted",
            }
        return _http_error(f"Deleting realm {name}", status_code, body)

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to delete realm {name}: {str(e)}",
        }


def events_config_present(
    realm,
    events_enabled=None,
    events_listeners=None,
    enabled_event_types=None,
    events_expiration=None,
    admin_events_enabled=None,
    admin_events_details_enabled=None,
    spec=None,
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
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

    Keycloak Admin REST API:
        GET/PUT admin/realms/{realm}/events/config

    Args:
        realm (str): Realm name.
        events_enabled (bool): Enable login event logging
        events_listeners (list): Event listener provider ids
        enabled_event_types (list): Event types to log
        events_expiration (int): Event expiration in seconds
        admin_events_enabled (bool): Enable admin event logging
        admin_events_details_enabled (bool): Include details in admin events
        spec (dict, optional): Full events config fields to merge over
            (and override) the fields built from the other kwargs
        keycloak_addr (str): Keycloak API address
            (default: k8s://keycloak/keycloak-service:8443)
        token (str): Bearer token; obtained via get_admin_token if not given
        realm_username (str): Admin username used to obtain a token
        realm_password (str): Admin password used to obtain a token
        admin_client_id (str): Client id used for the admin login (default: admin-cli)
        admin_client_secret (str): Client secret for confidential client login
        namespace (str): Namespace of the admin credentials Secret (default: keycloak)
        secret_name (str): Name of the admin credentials Secret (default: keycloak-admin)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message

    CLI Example:

        salt-call kinetic_keycloak.events_config_present realm=myrealm events_enabled=True
    """
    try:
        resolved_token = _resolve_token(
            token, keycloak_addr, "master", realm_username, realm_password,
            admin_client_id, admin_client_secret, namespace, secret_name, verify,
        )
        if not resolved_token:
            return {
                "success": False,
                "updated": False,
                "message": "Failed to obtain Keycloak admin access token",
            }
        headers = _auth_headers(resolved_token)

        field_map = {
            "events_enabled": "eventsEnabled",
            "events_listeners": "eventsListeners",
            "enabled_event_types": "enabledEventTypes",
            "events_expiration": "eventsExpiration",
            "admin_events_enabled": "adminEventsEnabled",
            "admin_events_details_enabled": "adminEventsDetailsEnabled",
        }
        local_vars = locals()
        desired = {
            camel: local_vars[snake]
            for snake, camel in field_map.items()
            if local_vars[snake] is not None
        }
        if spec:
            desired = {**desired, **spec}

        status_code, body = _request(
            "GET", keycloak_addr, f"admin/realms/{realm}/events/config",
            headers=headers, verify=verify,
        )
        if status_code != 200 or not isinstance(body, dict):
            return _http_error(
                f"Reading events config for realm {realm}", status_code, body
            )

        if all(body.get(k) == v for k, v in desired.items()):
            return {
                "success": True,
                "updated": False,
                "message": f"Events config for realm {realm} already matches desired state",
            }

        payload = {**body, **desired}
        status_code, body = _request(
            "PUT", keycloak_addr, f"admin/realms/{realm}/events/config",
            headers=headers, payload=payload, verify=verify,
        )
        if status_code == 204:
            return {
                "success": True,
                "updated": True,
                "message": f"Events config for realm {realm} updated",
            }
        return _http_error(f"Updating events config for realm {realm}", status_code, body)

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure events config for realm {realm}: {str(e)}",
        }


def required_action_present(
    realm,
    provider_id,
    alias=None,
    name=None,
    enabled=True,
    default_action=False,
    priority=None,
    config=None,
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
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

    Keycloak Admin REST API:
        POST admin/realms/{realm}/authentication/register-required-action
        GET/PUT admin/realms/{realm}/authentication/required-actions/{alias}

    Args:
        realm (str): Realm name.
        provider_id (str): Required action provider id (e.g. CONFIGURE_TOTP)
        alias (str): Required action alias (default: provider_id)
        name (str): Display name (default: provider_id, only used at registration)
        enabled (bool): Whether the required action is enabled (default: True)
        default_action (bool): Whether new users get this action by default
        priority (int): Ordering priority
        config (dict): Provider-specific configuration
        keycloak_addr (str): Keycloak API address
            (default: k8s://keycloak/keycloak-service:8443)
        token (str): Bearer token; obtained via get_admin_token if not given
        realm_username (str): Admin username used to obtain a token
        realm_password (str): Admin password used to obtain a token
        admin_client_id (str): Client id used for the admin login (default: admin-cli)
        admin_client_secret (str): Client secret for confidential client login
        namespace (str): Namespace of the admin credentials Secret (default: keycloak)
        secret_name (str): Name of the admin credentials Secret (default: keycloak-admin)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message

    CLI Example:

        salt-call kinetic_keycloak.required_action_present realm=myrealm provider_id=CONFIGURE_TOTP
    """
    if alias is None:
        alias = provider_id

    try:
        resolved_token = _resolve_token(
            token, keycloak_addr, "master", realm_username, realm_password,
            admin_client_id, admin_client_secret, namespace, secret_name, verify,
        )
        if not resolved_token:
            return {
                "success": False,
                "updated": False,
                "message": "Failed to obtain Keycloak admin access token",
            }
        headers = _auth_headers(resolved_token)

        status_code, body = _request(
            "GET", keycloak_addr,
            f"admin/realms/{realm}/authentication/required-actions/{alias}",
            headers=headers, verify=verify,
        )

        registered = False
        if status_code == 404:
            reg_payload = {"providerId": provider_id, "name": name or provider_id}
            status_code, body = _request(
                "POST", keycloak_addr,
                f"admin/realms/{realm}/authentication/register-required-action",
                headers=headers, payload=reg_payload, verify=verify,
            )
            if status_code not in (200, 201, 204):
                return _http_error(
                    f"Registering required action {alias}", status_code, body
                )

            status_code, body = _request(
                "GET", keycloak_addr,
                f"admin/realms/{realm}/authentication/required-actions/{alias}",
                headers=headers, verify=verify,
            )
            if status_code != 200 or not isinstance(body, dict):
                return {
                    "success": False,
                    "updated": False,
                    "message": (
                        f"Required action {alias} was registered but could not "
                        f"be read back for configuration (HTTP {status_code})"
                    ),
                }
            registered = True

        elif status_code != 200 or not isinstance(body, dict):
            return _http_error(f"Checking required action {alias}", status_code, body)

        current = body
        desired = {"alias": alias, "enabled": enabled, "defaultAction": default_action}
        if priority is not None:
            desired["priority"] = priority
        if config is not None:
            desired["config"] = config

        if all(current.get(k) == v for k, v in desired.items()):
            return {
                "success": True,
                "updated": registered,
                "message": f"Required action {alias} already matches desired state",
            }

        payload = {**current, **desired}
        status_code, body = _request(
            "PUT", keycloak_addr,
            f"admin/realms/{realm}/authentication/required-actions/{alias}",
            headers=headers, payload=payload, verify=verify,
        )
        if status_code == 204:
            return {
                "success": True,
                "updated": True,
                "message": f"Required action {alias} configured",
            }
        return _http_error(f"Configuring required action {alias}", status_code, body)

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure required action {alias}: {str(e)}",
        }


def authentication_flow_present(
    realm,
    alias,
    description=None,
    provider_id="basic-flow",
    top_level=True,
    built_in=False,
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
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

    Keycloak Admin REST API:
        GET/POST admin/realms/{realm}/authentication/flows
        PUT admin/realms/{realm}/authentication/flows/{id}

    Args:
        realm (str): Realm name.
        alias (str): Flow alias (unique name).
        description (str): Flow description.
        provider_id (str): Flow provider id (default: basic-flow)
        top_level (bool): Whether this is a top-level flow (default: True).
            Sub-flows (top_level=False) are not created via this function;
            they are created implicitly when referenced by a parent flow via
            authentication_execution_present(..., type="flow").
        keycloak_addr (str): Keycloak API address
            (default: k8s://keycloak/keycloak-service:8443)
        token (str): Bearer token; obtained via get_admin_token if not given
        realm_username (str): Admin username used to obtain a token
        realm_password (str): Admin password used to obtain a token
        admin_client_id (str): Client id used for the admin login (default: admin-cli)
        admin_client_secret (str): Client secret for confidential client login
        namespace (str): Namespace of the admin credentials Secret (default: keycloak)
        secret_name (str): Name of the admin credentials Secret (default: keycloak-admin)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message. The resolved flow id is included in
            the message as "(id: <id>)" when known, for informational use by
            callers (e.g. authentication_execution_present only needs the
            alias, so this is not a strict parsing contract).

    CLI Example:

        salt-call kinetic_keycloak.authentication_flow_present realm=myrealm alias=my-browser-flow
    """
    try:
        resolved_token = _resolve_token(
            token, keycloak_addr, "master", realm_username, realm_password,
            admin_client_id, admin_client_secret, namespace, secret_name, verify,
        )
        if not resolved_token:
            return {
                "success": False,
                "updated": False,
                "message": "Failed to obtain Keycloak admin access token",
            }
        headers = _auth_headers(resolved_token)

        status_code, body = _request(
            "GET", keycloak_addr, f"admin/realms/{realm}/authentication/flows",
            headers=headers, verify=verify,
        )
        if status_code != 200 or not isinstance(body, list):
            return _http_error("Listing authentication flows", status_code, body)

        existing = next((f for f in body if f.get("alias") == alias), None)

        if existing is None:
            if not top_level:
                # Sub-flows are created implicitly when referenced by a parent flow
                # via authentication_execution_present(..., type="flow")
                return {
                    "success": True,
                    "updated": False,
                    "message": f"Sub-flow {alias} will be created when referenced by a parent flow",
                }

            payload = {
                "alias": alias,
                "description": description or "",
                "providerId": provider_id,
                "topLevel": top_level,
                "builtIn": built_in,
            }
            status_code, body = _request(
                "POST", keycloak_addr, f"admin/realms/{realm}/authentication/flows",
                headers=headers, payload=payload, verify=verify,
            )
            if status_code == 201:
                new_id_suffix = ""
                if isinstance(body, dict) and body.get("id"):
                    new_id_suffix = f" (id: {body['id']})"
                return {
                    "success": True,
                    "updated": True,
                    "message": f"Authentication flow {alias} created{new_id_suffix}",
                }
            return _http_error(f"Creating authentication flow {alias}", status_code, body)

        flow_id = existing.get("id")
        id_suffix = f" (id: {flow_id})" if flow_id else ""
        desired_description = (
            description if description is not None else existing.get("description")
        )

        if existing.get("description") == desired_description:
            return {
                "success": True,
                "updated": False,
                "message": f"Authentication flow {alias} already matches desired state{id_suffix}",
            }

        payload = {**existing, "description": desired_description}
        status_code, body = _request(
            "PUT", keycloak_addr,
            f"admin/realms/{realm}/authentication/flows/{flow_id}",
            headers=headers, payload=payload, verify=verify,
        )
        if status_code in (200, 204):
            return {
                "success": True,
                "updated": True,
                "message": f"Authentication flow {alias} updated{id_suffix}",
            }

        detail = json.dumps(body) if isinstance(body, dict) else str(body)
        return {
            "success": False,
            "updated": False,
            "message": (
                f"Failed to update authentication flow {alias}{id_suffix}: "
                f"HTTP {status_code} - note alias/providerId are immutable and "
                f"only certain fields (e.g. description) can be changed: {detail[:200]}"
            ),
        }

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure authentication flow {alias}: {str(e)}",
        }


def authentication_flow_absent(
    realm,
    alias,
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
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

    Keycloak Admin REST API:
        GET admin/realms/{realm}/authentication/flows
        DELETE admin/realms/{realm}/authentication/flows/{id}

    Args:
        realm (str): Realm name.
        alias (str): Flow alias.
        keycloak_addr (str): Keycloak API address
            (default: k8s://keycloak/keycloak-service:8443)
        token (str): Bearer token; obtained via get_admin_token if not given
        realm_username (str): Admin username used to obtain a token
        realm_password (str): Admin password used to obtain a token
        admin_client_id (str): Client id used for the admin login (default: admin-cli)
        admin_client_secret (str): Client secret for confidential client login
        namespace (str): Namespace of the admin credentials Secret (default: keycloak)
        secret_name (str): Name of the admin credentials Secret (default: keycloak-admin)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message

    CLI Example:

        salt-call kinetic_keycloak.authentication_flow_absent realm=myrealm alias=my-browser-flow
    """
    try:
        resolved_token = _resolve_token(
            token, keycloak_addr, "master", realm_username, realm_password,
            admin_client_id, admin_client_secret, namespace, secret_name, verify,
        )
        if not resolved_token:
            return {
                "success": False,
                "updated": False,
                "message": "Failed to obtain Keycloak admin access token",
            }
        headers = _auth_headers(resolved_token)

        status_code, body = _request(
            "GET", keycloak_addr, f"admin/realms/{realm}/authentication/flows",
            headers=headers, verify=verify,
        )
        if status_code != 200 or not isinstance(body, list):
            return _http_error("Listing authentication flows", status_code, body)

        existing = next((f for f in body if f.get("alias") == alias), None)
        if existing is None:
            return {
                "success": True,
                "updated": False,
                "message": f"Authentication flow {alias} already absent",
            }

        flow_id = existing.get("id")
        status_code, body = _request(
            "DELETE", keycloak_addr,
            f"admin/realms/{realm}/authentication/flows/{flow_id}",
            headers=headers, verify=verify,
        )
        if status_code == 204:
            return {
                "success": True,
                "updated": True,
                "message": f"Authentication flow {alias} deleted",
            }
        return _http_error(f"Deleting authentication flow {alias}", status_code, body)

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to delete authentication flow {alias}: {str(e)}",
        }


def authentication_execution_present(
    realm,
    flow_alias,
    provider_id,
    requirement="DISABLED",
    type="execution",          # "execution" or "flow"
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
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
    requirement (e.g. DISABLED, ALTERNATIVE, REQUIRED, CONDITIONAL).

    Note: execution priority/ordering (raise-priority/lower-priority) is not
    managed by this function.

    Keycloak Admin REST API:
        GET admin/realms/{realm}/authentication/flows/{flowAlias}/executions
        POST admin/realms/{realm}/authentication/flows/{flowAlias}/executions/execution
        PUT admin/realms/{realm}/authentication/flows/{flowAlias}/executions

    Args:
        realm (str): Realm name.
        flow_alias (str): Alias of the flow to add/update the execution in.
        provider_id (str): Execution provider id (or sub-flow alias when type="flow").
        requirement (str): Execution requirement (default: DISABLED)
        type (str): "execution" (default) or "flow" (to register a sub-flow)
        keycloak_addr (str): Keycloak API address
            (default: k8s://keycloak/keycloak-service:8443)
        token (str): Bearer token; obtained via get_admin_token if not given
        realm_username (str): Admin username used to obtain a token
        realm_password (str): Admin password used to obtain a token
        admin_client_id (str): Client id used for the admin login (default: admin-cli)
        admin_client_secret (str): Client secret for confidential client login
        namespace (str): Namespace of the admin credentials Secret (default: keycloak)
        secret_name (str): Name of the admin credentials Secret (default: keycloak-admin)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message

    CLI Example:

        salt-call kinetic_keycloak.authentication_execution_present realm=myrealm flow_alias=my-browser-flow provider_id=auth-otp-form requirement=REQUIRED
    """
    try:
        resolved_token = _resolve_token(
            token, keycloak_addr, "master", realm_username, realm_password,
            admin_client_id, admin_client_secret, namespace, secret_name, verify,
        )
        if not resolved_token:
            return {
                "success": False,
                "updated": False,
                "message": "Failed to obtain Keycloak admin access token",
            }
        headers = _auth_headers(resolved_token)

        executions_path = (
            f"admin/realms/{realm}/authentication/flows/{flow_alias}/executions"
        )
        status_code, body = _request(
            "GET", keycloak_addr, executions_path, headers=headers, verify=verify
        )
        if status_code != 200 or not isinstance(body, list):
            return _http_error(
                f"Listing executions for flow {flow_alias}", status_code, body
            )

        # For sub-flow executions, match on authenticationFlow + alias/displayName
        # instead of providerId (which is the sub-flow provider, e.g. basic-flow).
        # Comparisons are normalized (trimmed + lowercased) to tolerate minor
        # formatting differences across Keycloak versions.
        def _norm(value):
            return value.strip().lower() if isinstance(value, str) else value

        def _matches(e):
            if type == "flow":
                if not e.get("authenticationFlow"):
                    return False
                return _norm(e.get("alias")) == _norm(provider_id) or _norm(
                    e.get("displayName")
                ) == _norm(provider_id)
            return e.get("providerId") == provider_id

        execution = next((e for e in body if _matches(e)), None)
        created = False

        if execution is None:
            if type == "flow":
                # Register a sub-flow
                payload = {
                    "alias": provider_id,
                    "type": "basic-flow",
                    "provider": "basic-flow",
                }
                status_code, add_body = _request(
                    "POST", keycloak_addr, f"{executions_path}/flow",
                    headers=headers, payload=payload, verify=verify,
                )
            else:
                # Register a normal execution
                status_code, add_body = _request(
                    "POST", keycloak_addr, f"{executions_path}/execution",
                    headers=headers, payload={"provider": provider_id}, verify=verify,
                )

            already_exists = (
                status_code == 409
                and isinstance(add_body, dict)
                and "already exists" in str(add_body.get("errorMessage", "")).lower()
            )

            if status_code not in (200, 201, 204) and not already_exists:
                return _http_error(
                    f"Adding {type} {provider_id} to flow {flow_alias}",
                    status_code, add_body,
                )
            created = not already_exists

            status_code, body = _request(
                "GET", keycloak_addr, executions_path, headers=headers, verify=verify
            )
            if status_code != 200 or not isinstance(body, list):
                return _http_error(
                    f"Listing executions for flow {flow_alias}", status_code, body
                )
            execution = next((e for e in body if _matches(e)), None)
            if execution is None:
                if already_exists:
                    # Keycloak reports the alias already exists (e.g. as an
                    # orphaned flow from an earlier partial run), but it is
                    # not linked under this parent flow. Manual cleanup of
                    # the orphaned flow alias may be required in Keycloak.
                    return {
                        "success": False,
                        "updated": False,
                        "message": (
                            f"{type.capitalize()} alias {provider_id} already exists in "
                            f"realm {realm} but is not linked under flow {flow_alias}. "
                            f"It may be an orphaned flow from a previous run - check "
                            f"the realm's authentication flows in Keycloak and remove "
                            f"or rename the conflicting flow."
                        ),
                    }
                return {
                    "success": False,
                    "updated": False,
                    "message": (
                        f"{type.capitalize()} {provider_id} was added to flow {flow_alias} "
                        f"but could not be found afterwards"
                    ),
                }

        if execution.get("requirement") == requirement:
            return {
                "success": True,
                "updated": created,
                "message": (
                    f"Execution {provider_id} in flow {flow_alias} already "
                    f"matches desired state"
                ),
            }

        payload = {**execution, "requirement": requirement}
        status_code, body = _request(
            "PUT", keycloak_addr, executions_path,
            headers=headers, payload=payload, verify=verify,
        )
        if status_code == 204:
            return {
                "success": True,
                "updated": True,
                "message": (
                    f"Execution {provider_id} in flow {flow_alias} requirement "
                    f"set to {requirement}"
                ),
            }
        return _http_error(
            f"Updating execution {provider_id} requirement in flow {flow_alias}",
            status_code, body,
        )

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": (
                f"Failed to ensure execution {provider_id} in flow "
                f"{flow_alias}: {str(e)}"
            ),
        }


def client_present(
    realm,
    client_id,
    name=None,
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
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
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

    For public clients, PKCE is enabled by default (S256) unless explicitly
    overridden via pkce_code_challenge_method or attributes, since public
    clients cannot securely hold a client secret and are therefore more
    exposed to authorization code interception.

    client_id is Keycloak's "clientId" (the human-readable identifier), not
    the internal UUID "id" used in the REST paths once the client exists.

    Keycloak Admin REST API:
        GET/POST admin/realms/{realm}/clients
        GET/PUT admin/realms/{realm}/clients/{id}

    Args:
        realm (str): Realm name.
        client_id (str): Keycloak clientId of the client to manage.
        name (str): Display name.
        description (str): Description.
        enabled (bool): Whether the client is enabled (default: True)
        protocol (str): Client protocol (default: openid-connect)
        public_client (bool): Whether the client is public (default: False)
        standard_flow_enabled (bool): Enable the authorization code flow (default: True)
        direct_access_grants_enabled (bool): Enable the resource owner password
            grant (default: True)
        service_accounts_enabled (bool): Enable the client credentials grant
            (default: False)
        authorization_services_enabled (bool): Enable fine-grained authorization
            (default: False)
        redirect_uris (list): Valid redirect URIs
        web_origins (list): Allowed CORS origins
        root_url (str): Root URL
        base_url (str): Base URL
        client_authenticator_type (str): Client authenticator type
            (default: client-secret)
        secret (str): Client secret to force-set. Keycloak never returns the
            secret in GET responses for confidential clients, so it is
            excluded from the idempotency comparison, but is still sent in
            the PUT/POST body when provided.
        pkce_code_challenge_method (str, optional): PKCE code challenge
            method (e.g. S256, plain). Sets the client attribute
            pkce.code.challenge.method. Defaults to "S256" for public
            clients (public_client=True) unless explicitly set here or in
            attributes/spec; not defaulted for confidential clients. Pass an
            empty string to explicitly disable PKCE enforcement for a
            public client.
        attributes (dict, optional): Free-form client attributes to merge
            into (not replace) the client's existing attributes map. Useful
            for attributes not covered by other kwargs.
        spec (dict, optional): Full client representation fields to merge
            over (and override) the fields built from the other kwargs
        keycloak_addr (str): Keycloak API address
            (default: k8s://keycloak/keycloak-service:8443)
        token (str): Bearer token; obtained via get_admin_token if not given
        realm_username (str): Admin username used to obtain a token
        realm_password (str): Admin password used to obtain a token
        admin_client_id (str): Client id used for the admin login (default: admin-cli)
        admin_client_secret (str): Client secret for confidential client login
        namespace (str): Namespace of the admin credentials Secret (default: keycloak)
        secret_name (str): Name of the admin credentials Secret (default: keycloak-admin)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message

    CLI Example:

        salt-call kinetic_keycloak.client_present realm=myrealm client_id=my-app
    """
    try:
        resolved_token = _resolve_token(
            token, keycloak_addr, "master", realm_username, realm_password,
            admin_client_id, admin_client_secret, namespace, secret_name, verify,
        )
        if not resolved_token:
            return {
                "success": False,
                "updated": False,
                "message": "Failed to obtain Keycloak admin access token",
            }
        headers = _auth_headers(resolved_token)

        desired = {
            "clientId": client_id,
            "enabled": enabled,
            "protocol": protocol,
            "publicClient": public_client,
            "standardFlowEnabled": standard_flow_enabled,
            "directAccessGrantsEnabled": direct_access_grants_enabled,
            "serviceAccountsEnabled": service_accounts_enabled,
            "authorizationServicesEnabled": authorization_services_enabled,
            "clientAuthenticatorType": client_authenticator_type,
        }
        optional_map = {
            "name": name,
            "description": description,
            "redirectUris": redirect_uris,
            "webOrigins": web_origins,
            "rootUrl": root_url,
            "baseUrl": base_url,
        }
        for camel, value in optional_map.items():
            if value is not None:
                desired[camel] = value
        if secret is not None:
            desired["secret"] = secret

        merged_attributes = dict(attributes) if attributes else {}
        if "pkce.code.challenge.method" not in merged_attributes:
            if pkce_code_challenge_method is not None:
                merged_attributes["pkce.code.challenge.method"] = pkce_code_challenge_method
            elif public_client:
                # Public clients cannot securely hold a client secret, so
                # enforce PKCE (S256) by default to protect the
                # authorization code from interception.
                merged_attributes["pkce.code.challenge.method"] = "S256"
        if merged_attributes:
            desired["attributes"] = merged_attributes

        if spec:
            desired = {**desired, **spec}

        status_code, body = _request(
            "GET", keycloak_addr, f"admin/realms/{realm}/clients?clientId={client_id}",
            headers=headers, verify=verify,
        )
        if status_code != 200 or not isinstance(body, list):
            return _http_error(
                f"Listing clients for clientId {client_id}", status_code, body
            )

        existing = body[0] if body else None

        if existing is None:
            status_code, body = _request(
                "POST", keycloak_addr, f"admin/realms/{realm}/clients",
                headers=headers, payload=desired, verify=verify,
            )
            if status_code == 201:
                return {
                    "success": True,
                    "updated": True,
                    "message": f"Client {client_id} created in realm {realm}",
                }
            return _http_error(f"Creating client {client_id}", status_code, body)

        # Keycloak auto-populates many other client attributes (e.g.
        # client.secret.creation.time), so attributes are compared and
        # merged as a subset rather than requiring full-dict equality.
        desired_attributes = desired.get("attributes")
        comparable = {k: v for k, v in desired.items() if k not in ("secret", "attributes")}
        attributes_match = True
        if desired_attributes is not None:
            existing_attributes = existing.get("attributes") or {}
            attributes_match = all(
                str(existing_attributes.get(k)) == str(v) for k, v in desired_attributes.items()
            )
        if attributes_match and all(existing.get(k) == v for k, v in comparable.items()):
            return {
                "success": True,
                "updated": False,
                "message": f"Client {client_id} already exists and matches desired state",
            }

        internal_id = existing.get("id")
        payload = {**existing, **desired}
        if desired_attributes is not None:
            payload["attributes"] = {**(existing.get("attributes") or {}), **desired_attributes}
        status_code, body = _request(
            "PUT", keycloak_addr, f"admin/realms/{realm}/clients/{internal_id}",
            headers=headers, payload=payload, verify=verify,
        )
        if status_code == 204:
            return {
                "success": True,
                "updated": True,
                "message": f"Client {client_id} updated in realm {realm}",
            }
        return _http_error(f"Updating client {client_id}", status_code, body)

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure client {client_id}: {str(e)}",
        }


def client_default_scope_present(
    realm,
    client_id,
    scope_name,
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
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

    This is additive/idempotent: it only assigns the given scope and never
    removes any other default or optional client scopes already present on
    the client (unlike setting `defaultClientScopes` directly on the client
    representation, which would require specifying the full list and risks
    dropping Keycloak's built-in defaults like profile/email/roles).

    Keycloak Admin REST API:
        GET admin/realms/{realm}/clients?clientId={clientId}
        GET admin/realms/{realm}/client-scopes
        PUT admin/realms/{realm}/clients/{id}/default-client-scopes/{scopeId}

    Args:
        realm (str): Realm name.
        client_id (str): Keycloak clientId of the client to manage.
        scope_name (str): Name of the client scope to assign as default
            (e.g. "groups"). Must already exist in the realm.
        keycloak_addr (str): Keycloak API address.
        token (str): Bearer token; obtained via get_admin_token if not given.
        realm_username (str): Admin username used to obtain a token.
        realm_password (str): Admin password used to obtain a token.
        admin_client_id (str): Client id used for the admin login.
        admin_client_secret (str): Client secret for confidential client login.
        namespace (str): Namespace of the admin credentials Secret.
        secret_name (str): Name of the admin credentials Secret.
        verify (bool): Verify TLS certificates.

    Returns:
        dict: success, updated, message

    CLI Example:

        salt-call kinetic_keycloak.client_default_scope_present realm=myrealm client_id=my-app scope_name=groups
    """
    try:
        resolved_token = _resolve_token(
            token, keycloak_addr, "master", realm_username, realm_password,
            admin_client_id, admin_client_secret, namespace, secret_name, verify,
        )
        if not resolved_token:
            return {
                "success": False,
                "updated": False,
                "message": "Failed to obtain Keycloak admin access token",
            }
        headers = _auth_headers(resolved_token)

        status_code, body = _request(
            "GET", keycloak_addr, f"admin/realms/{realm}/clients?clientId={client_id}",
            headers=headers, verify=verify,
        )
        if status_code != 200 or not isinstance(body, list) or not body:
            return _http_error(f"Looking up client {client_id}", status_code, body)
        client = body[0]
        internal_id = client.get("id")
        current_default_scopes = client.get("defaultClientScopes") or []
        if scope_name in current_default_scopes:
            return {
                "success": True,
                "updated": False,
                "message": f"Client {client_id} already has default client scope {scope_name}",
            }

        status_code, body = _request(
            "GET", keycloak_addr, f"admin/realms/{realm}/client-scopes",
            headers=headers, verify=verify,
        )
        if status_code != 200 or not isinstance(body, list):
            return _http_error(f"Listing client scopes in realm {realm}", status_code, body)
        scope = next((s for s in body if s.get("name") == scope_name), None)
        if scope is None:
            return {
                "success": False,
                "updated": False,
                "message": f"Client scope {scope_name} does not exist in realm {realm}",
            }
        scope_id = scope.get("id")

        status_code, body = _request(
            "PUT", keycloak_addr,
            f"admin/realms/{realm}/clients/{internal_id}/default-client-scopes/{scope_id}",
            headers=headers, verify=verify,
        )
        if status_code == 204:
            return {
                "success": True,
                "updated": True,
                "message": f"Assigned default client scope {scope_name} to client {client_id}",
            }
        return _http_error(
            f"Assigning default client scope {scope_name} to client {client_id}", status_code, body
        )
    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure default client scope {scope_name} on client {client_id}: {str(e)[:150]}",
        }


def client_absent(
    realm,
    client_id,
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
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

    Keycloak Admin REST API:
        GET admin/realms/{realm}/clients
        DELETE admin/realms/{realm}/clients/{id}

    Args:
        realm (str): Realm name.
        client_id (str): Keycloak clientId of the client to remove.
        keycloak_addr (str): Keycloak API address
            (default: k8s://keycloak/keycloak-service:8443)
        token (str): Bearer token; obtained via get_admin_token if not given
        realm_username (str): Admin username used to obtain a token
        realm_password (str): Admin password used to obtain a token
        admin_client_id (str): Client id used for the admin login (default: admin-cli)
        admin_client_secret (str): Client secret for confidential client login
        namespace (str): Namespace of the admin credentials Secret (default: keycloak)
        secret_name (str): Name of the admin credentials Secret (default: keycloak-admin)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message

    CLI Example:

        salt-call kinetic_keycloak.client_absent realm=myrealm client_id=my-app
    """
    try:
        resolved_token = _resolve_token(
            token, keycloak_addr, "master", realm_username, realm_password,
            admin_client_id, admin_client_secret, namespace, secret_name, verify,
        )
        if not resolved_token:
            return {
                "success": False,
                "updated": False,
                "message": "Failed to obtain Keycloak admin access token",
            }
        headers = _auth_headers(resolved_token)

        status_code, body = _request(
            "GET", keycloak_addr, f"admin/realms/{realm}/clients?clientId={client_id}",
            headers=headers, verify=verify,
        )
        if status_code != 200 or not isinstance(body, list):
            return _http_error(
                f"Listing clients for clientId {client_id}", status_code, body
            )

        if not body:
            return {
                "success": True,
                "updated": False,
                "message": f"Client {client_id} already absent",
            }

        internal_id = body[0].get("id")
        status_code, body = _request(
            "DELETE", keycloak_addr, f"admin/realms/{realm}/clients/{internal_id}",
            headers=headers, verify=verify,
        )
        if status_code == 204:
            return {
                "success": True,
                "updated": True,
                "message": f"Client {client_id} deleted",
            }
        return _http_error(f"Deleting client {client_id}", status_code, body)

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to delete client {client_id}: {str(e)}",
        }


def user_federation_present(
    realm,
    name,
    provider_id="ldap",
    provider_type="org.keycloak.storage.UserStorageProvider",
    parent_id=None,
    start_tls=None,
    use_truststore_spi=None,
    config=None,
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
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

    Keycloak Admin REST API:
        GET/POST admin/realms/{realm}/components
        GET/PUT admin/realms/{realm}/components/{id}

    Args:
        realm (str): Realm name.
        name (str): Component name.
        provider_id (str): Provider id (default: ldap)
        provider_type (str): Component provider type
            (default: org.keycloak.storage.UserStorageProvider)
        parent_id (str): Parent id (default: realm, for realm-level providers)
        start_tls (bool): Use StartTLS to negotiate encryption on the plain
            LDAP port (config key startTls). Sets config["startTls"] unless
            already set in config.
        use_truststore_spi (str): When to use Keycloak's truststore SPI for
            LDAP connections (config key useTruststoreSpi); one of "always",
            "ldapsOnly", or "never". Sets config["useTruststoreSpi"] unless
            already set in config.
        config (dict): Provider config; values are normalized to List[str]
            as required by the Keycloak component representation. Explicit
            startTls/useTruststoreSpi keys in config take precedence over
            the start_tls/use_truststore_spi kwargs.
        keycloak_addr (str): Keycloak API address
            (default: k8s://keycloak/keycloak-service:8443)
        token (str): Bearer token; obtained via get_admin_token if not given
        realm_username (str): Admin username used to obtain a token
        realm_password (str): Admin password used to obtain a token
        admin_client_id (str): Client id used for the admin login (default: admin-cli)
        admin_client_secret (str): Client secret for confidential client login
        namespace (str): Namespace of the admin credentials Secret (default: keycloak)
        secret_name (str): Name of the admin credentials Secret (default: keycloak-admin)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message

    CLI Example:

        salt-call kinetic_keycloak.user_federation_present realm=myrealm name=corp-ldap
    """
    try:
        resolved_token = _resolve_token(
            token, keycloak_addr, "master", realm_username, realm_password,
            admin_client_id, admin_client_secret, namespace, secret_name, verify,
        )
        if not resolved_token:
            return {
                "success": False,
                "updated": False,
                "message": "Failed to obtain Keycloak admin access token",
            }
        headers = _auth_headers(resolved_token)

        if parent_id is None:
            # Realm-level components (e.g. LDAP user federation) must be
            # parented to the realm's internal id (a UUID assigned by
            # Keycloak), which is generally NOT the same as the realm name.
            # Falling back to the realm name here would silently create
            # components with a bogus parentId that never show up in the
            # admin console.
            status_code, realm_body = _request(
                "GET", keycloak_addr, f"admin/realms/{realm}",
                headers=headers, verify=verify,
            )
            if status_code == 200 and isinstance(realm_body, dict) and realm_body.get("id"):
                parent_id = realm_body["id"]
            else:
                return _http_error(
                    f"Resolving internal id for realm {realm}", status_code, realm_body
                )

        merged_config = {}
        if start_tls is not None:
            merged_config["startTls"] = "true" if start_tls else "false"
        if use_truststore_spi is not None:
            merged_config["useTruststoreSpi"] = use_truststore_spi
        if config:
            merged_config.update(config)
        normalized_config = _to_component_config(merged_config)

        status_code, body = _request(
            "GET", keycloak_addr,
            f"admin/realms/{realm}/components?parent={parent_id}&type={provider_type}",
            headers=headers, verify=verify,
        )
        if status_code != 200 or not isinstance(body, list):
            return _http_error(
                f"Listing user federation components in realm {realm}",
                status_code, body,
            )

        existing = next((c for c in body if c.get("name") == name), None)

        desired = {
            "name": name,
            "providerId": provider_id,
            "providerType": provider_type,
            "parentId": parent_id,
            "config": normalized_config,
        }

        if existing is None:
            status_code, body = _request(
                "POST", keycloak_addr, f"admin/realms/{realm}/components",
                headers=headers, payload=desired, verify=verify,
            )
            if status_code == 201:
                return {
                    "success": True,
                    "updated": True,
                    "message": f"User federation provider {name} created in realm {realm}",
                }
            return _http_error(
                f"Creating user federation provider {name}", status_code, body
            )

        current_config = _to_component_config(existing.get("config"))
        if existing.get("providerId") == provider_id and current_config == normalized_config:
            return {
                "success": True,
                "updated": False,
                "message": f"User federation provider {name} already matches desired state",
            }

        component_id = existing.get("id")
        payload = {**existing, **desired}
        status_code, body = _request(
            "PUT", keycloak_addr, f"admin/realms/{realm}/components/{component_id}",
            headers=headers, payload=payload, verify=verify,
        )
        if status_code == 204:
            return {
                "success": True,
                "updated": True,
                "message": f"User federation provider {name} updated in realm {realm}",
            }
        return _http_error(
            f"Updating user federation provider {name}", status_code, body
        )

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure user federation provider {name}: {str(e)}",
        }


def user_federation_absent(
    realm,
    name,
    provider_type="org.keycloak.storage.UserStorageProvider",
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
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

    Keycloak Admin REST API:
        GET admin/realms/{realm}/components
        DELETE admin/realms/{realm}/components/{id}

    Args:
        realm (str): Realm name.
        name (str): Component name.
        provider_type (str): Component provider type
            (default: org.keycloak.storage.UserStorageProvider)
        keycloak_addr (str): Keycloak API address
            (default: k8s://keycloak/keycloak-service:8443)
        token (str): Bearer token; obtained via get_admin_token if not given
        realm_username (str): Admin username used to obtain a token
        realm_password (str): Admin password used to obtain a token
        admin_client_id (str): Client id used for the admin login (default: admin-cli)
        admin_client_secret (str): Client secret for confidential client login
        namespace (str): Namespace of the admin credentials Secret (default: keycloak)
        secret_name (str): Name of the admin credentials Secret (default: keycloak-admin)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message

    CLI Example:

        salt-call kinetic_keycloak.user_federation_absent realm=myrealm name=corp-ldap
    """
    try:
        resolved_token = _resolve_token(
            token, keycloak_addr, "master", realm_username, realm_password,
            admin_client_id, admin_client_secret, namespace, secret_name, verify,
        )
        if not resolved_token:
            return {
                "success": False,
                "updated": False,
                "message": "Failed to obtain Keycloak admin access token",
            }
        headers = _auth_headers(resolved_token)

        status_code, body = _request(
            "GET", keycloak_addr,
            f"admin/realms/{realm}/components?type={provider_type}",
            headers=headers, verify=verify,
        )
        if status_code != 200 or not isinstance(body, list):
            return _http_error(
                f"Listing user federation components in realm {realm}",
                status_code, body,
            )

        existing = next((c for c in body if c.get("name") == name), None)
        if existing is None:
            return {
                "success": True,
                "updated": False,
                "message": f"User federation provider {name} already absent",
            }

        component_id = existing.get("id")
        status_code, body = _request(
            "DELETE", keycloak_addr, f"admin/realms/{realm}/components/{component_id}",
            headers=headers, verify=verify,
        )
        if status_code == 204:
            return {
                "success": True,
                "updated": True,
                "message": f"User federation provider {name} deleted",
            }
        return _http_error(
            f"Deleting user federation provider {name}", status_code, body
        )

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to delete user federation provider {name}: {str(e)}",
        }


def _resolve_realm_id(realm, keycloak_addr, headers, verify):
    """
    Resolve a realm's internal id (a server-assigned UUID, distinct from the
    realm name) via GET admin/realms/{realm}.

    Returns:
        tuple: (realm_id, error_dict). error_dict is None on success, or a
            standard failure return dict (from _http_error) on failure.
    """
    status_code, body = _request(
        "GET", keycloak_addr, f"admin/realms/{realm}", headers=headers, verify=verify,
    )
    if status_code == 200 and isinstance(body, dict) and body.get("id"):
        return body["id"], None
    return None, _http_error(f"Resolving internal id for realm {realm}", status_code, body)


def _resolve_federation_id(realm, federation_name, realm_id, keycloak_addr, headers, verify):
    """
    Resolve the internal component id of a realm-level user storage
    federation provider (e.g. LDAP) by its component name.

    Returns:
        tuple: (federation_id, error_dict). error_dict is None on success, or
            a standard failure return dict (from _http_error, or a
            not-found message) on failure.
    """
    status_code, body = _request(
        "GET", keycloak_addr,
        f"admin/realms/{realm}/components?parent={realm_id}"
        f"&type=org.keycloak.storage.UserStorageProvider",
        headers=headers, verify=verify,
    )
    if status_code != 200 or not isinstance(body, list):
        return None, _http_error(
            f"Listing user federation providers in realm {realm}", status_code, body
        )
    federation = next((c for c in body if c.get("name") == federation_name), None)
    if federation is None or not federation.get("id"):
        return None, {
            "success": False,
            "updated": False,
            "message": (
                f"User federation provider {federation_name} not found in realm {realm}"
            ),
        }
    return federation["id"], None


def ldap_mapper_present(
    realm,
    federation_name,
    name,
    provider_id,
    config=None,
    provider_type="org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
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

    Keycloak Admin REST API:
        GET/POST admin/realms/{realm}/components
        GET/PUT admin/realms/{realm}/components/{id}

    Args:
        realm (str): Realm name.
        federation_name (str): Name of the parent user federation provider
            component (as set via user_federation_present's name).
        name (str): Component name for this mapper.
        provider_id (str): Mapper provider id (e.g. group-ldap-mapper).
        config (dict): Mapper config; values are normalized to List[str] as
            required by the Keycloak component representation.
        provider_type (str): Component provider type (default:
            org.keycloak.storage.ldap.mappers.LDAPStorageMapper)
        keycloak_addr (str): Keycloak API address
            (default: k8s://keycloak/keycloak-service:8443)
        token (str): Bearer token; obtained via get_admin_token if not given
        realm_username (str): Admin username used to obtain a token
        realm_password (str): Admin password used to obtain a token
        admin_client_id (str): Client id used for the admin login (default: admin-cli)
        admin_client_secret (str): Client secret for confidential client login
        namespace (str): Namespace of the admin credentials Secret (default: keycloak)
        secret_name (str): Name of the admin credentials Secret (default: keycloak-admin)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message

    CLI Example:

        salt-call kinetic_keycloak.ldap_mapper_present realm=myrealm \
            federation_name=corp-ldap name=corp-ldap-groups provider_id=group-ldap-mapper
    """
    try:
        resolved_token = _resolve_token(
            token, keycloak_addr, "master", realm_username, realm_password,
            admin_client_id, admin_client_secret, namespace, secret_name, verify,
        )
        if not resolved_token:
            return {
                "success": False,
                "updated": False,
                "message": "Failed to obtain Keycloak admin access token",
            }
        headers = _auth_headers(resolved_token)

        realm_id, error = _resolve_realm_id(realm, keycloak_addr, headers, verify)
        if error:
            return error

        federation_id, error = _resolve_federation_id(
            realm, federation_name, realm_id, keycloak_addr, headers, verify
        )
        if error:
            return error

        normalized_config = _to_component_config(config)

        status_code, body = _request(
            "GET", keycloak_addr,
            f"admin/realms/{realm}/components?parent={federation_id}&type={provider_type}",
            headers=headers, verify=verify,
        )
        if status_code != 200 or not isinstance(body, list):
            return _http_error(
                f"Listing LDAP mappers for federation provider {federation_name} "
                f"in realm {realm}",
                status_code, body,
            )

        existing = next((c for c in body if c.get("name") == name), None)

        desired = {
            "name": name,
            "providerId": provider_id,
            "providerType": provider_type,
            "parentId": federation_id,
            "config": normalized_config,
        }

        if existing is None:
            status_code, body = _request(
                "POST", keycloak_addr, f"admin/realms/{realm}/components",
                headers=headers, payload=desired, verify=verify,
            )
            if status_code == 201:
                return {
                    "success": True,
                    "updated": True,
                    "message": (
                        f"LDAP mapper {name} created for federation provider "
                        f"{federation_name} in realm {realm}"
                    ),
                }
            return _http_error(f"Creating LDAP mapper {name}", status_code, body)

        current_config = _to_component_config(existing.get("config"))
        if existing.get("providerId") == provider_id and current_config == normalized_config:
            return {
                "success": True,
                "updated": False,
                "message": f"LDAP mapper {name} already matches desired state",
            }

        component_id = existing.get("id")
        payload = {**existing, **desired}
        status_code, body = _request(
            "PUT", keycloak_addr, f"admin/realms/{realm}/components/{component_id}",
            headers=headers, payload=payload, verify=verify,
        )
        if status_code == 204:
            return {
                "success": True,
                "updated": True,
                "message": (
                    f"LDAP mapper {name} updated for federation provider "
                    f"{federation_name} in realm {realm}"
                ),
            }
        return _http_error(f"Updating LDAP mapper {name}", status_code, body)

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to ensure LDAP mapper {name}: {str(e)}",
        }


def ldap_mapper_absent(
    realm,
    federation_name,
    name,
    provider_type="org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
    keycloak_addr=DEFAULT_KEYCLOAK_ADDR,
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

    Keycloak Admin REST API:
        GET admin/realms/{realm}/components
        DELETE admin/realms/{realm}/components/{id}

    Args:
        realm (str): Realm name.
        federation_name (str): Name of the parent user federation provider
            component (as set via user_federation_present's name).
        name (str): Component name for this mapper.
        provider_type (str): Component provider type (default:
            org.keycloak.storage.ldap.mappers.LDAPStorageMapper)
        keycloak_addr (str): Keycloak API address
            (default: k8s://keycloak/keycloak-service:8443)
        token (str): Bearer token; obtained via get_admin_token if not given
        realm_username (str): Admin username used to obtain a token
        realm_password (str): Admin password used to obtain a token
        admin_client_id (str): Client id used for the admin login (default: admin-cli)
        admin_client_secret (str): Client secret for confidential client login
        namespace (str): Namespace of the admin credentials Secret (default: keycloak)
        secret_name (str): Name of the admin credentials Secret (default: keycloak-admin)
        verify (bool): Verify TLS certificates (default: False)

    Returns:
        dict: success, updated, message

    CLI Example:

        salt-call kinetic_keycloak.ldap_mapper_absent realm=myrealm \
            federation_name=corp-ldap name=corp-ldap-groups
    """
    try:
        resolved_token = _resolve_token(
            token, keycloak_addr, "master", realm_username, realm_password,
            admin_client_id, admin_client_secret, namespace, secret_name, verify,
        )
        if not resolved_token:
            return {
                "success": False,
                "updated": False,
                "message": "Failed to obtain Keycloak admin access token",
            }
        headers = _auth_headers(resolved_token)

        realm_id, error = _resolve_realm_id(realm, keycloak_addr, headers, verify)
        if error:
            return error

        federation_id, error = _resolve_federation_id(
            realm, federation_name, realm_id, keycloak_addr, headers, verify
        )
        if error:
            # If the parent federation provider itself is already gone, the
            # mapper is necessarily absent too.
            return {
                "success": True,
                "updated": False,
                "message": (
                    f"LDAP mapper {name} already absent (federation provider "
                    f"{federation_name} not found in realm {realm})"
                ),
            }

        status_code, body = _request(
            "GET", keycloak_addr,
            f"admin/realms/{realm}/components?parent={federation_id}&type={provider_type}",
            headers=headers, verify=verify,
        )
        if status_code != 200 or not isinstance(body, list):
            return _http_error(
                f"Listing LDAP mappers for federation provider {federation_name} "
                f"in realm {realm}",
                status_code, body,
            )

        existing = next((c for c in body if c.get("name") == name), None)
        if existing is None:
            return {
                "success": True,
                "updated": False,
                "message": f"LDAP mapper {name} already absent",
            }

        component_id = existing.get("id")
        status_code, body = _request(
            "DELETE", keycloak_addr, f"admin/realms/{realm}/components/{component_id}",
            headers=headers, verify=verify,
        )
        if status_code == 204:
            return {
                "success": True,
                "updated": True,
                "message": f"LDAP mapper {name} deleted",
            }
        return _http_error(f"Deleting LDAP mapper {name}", status_code, body)

    except Exception as e:
        return {
            "success": False,
            "updated": False,
            "message": f"Failed to delete LDAP mapper {name}: {str(e)}",
        }
