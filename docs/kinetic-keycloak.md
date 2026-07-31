# kinetic-keycloak Module

SaltStack execution module (`kinetic_keycloak`) and state module (`keycloak`) for managing a Keycloak realm via its Admin REST API. This talks directly to the Keycloak Admin REST API - it does not use `kubectl exec` and is separate from the `k8s.keycloak_cluster_present` state, which manages the Keycloak Operator custom resource (the deployment itself, not its realm configuration).

## Transport

Every function accepts a `keycloak_addr` connection kwarg with two supported schemes:

- `k8s://<namespace>/<service>:<port>` (default: `k8s://keycloak/keycloak-service:8443`) - routes requests through the Kubernetes API server's service proxy, so the Keycloak Admin API never needs to be exposed outside the cluster. Only Kubernetes API access is required.
- `https://host:port` - direct HTTPS, for when the Admin API is reachable directly.

## Authentication

All functions resolve a bearer token automatically:

1. If a `token` kwarg is passed, it is used as-is.
2. Otherwise, `get_admin_token()` is called, which:
   - Uses `realm_username`/`realm_password` if provided, or `admin_client_id`/`admin_client_secret` for a client-credentials grant.
   - Otherwise reads admin credentials from a Kubernetes Secret (`namespace`/`secret_name`, default `keycloak`/`keycloak-admin`, keys `username`/`password`).
   - Performs a form-encoded login against `realms/master/protocol/openid-connect/token`.

Keycloak access tokens are short-lived (~60s by default), so a fresh token is fetched on every call rather than cached.

### Common connection kwargs

Every function below accepts these trailing kwargs (omitted from the per-function lists for brevity):

```
keycloak_addr="k8s://keycloak/keycloak-service:8443"
token=None
realm_username=None
realm_password=None
admin_client_id="admin-cli"
admin_client_secret=None
namespace="keycloak"
secret_name="keycloak-admin"
verify=False
```

All functions return `{"success": bool, "updated": bool, "message": str}`.

## Functions / Feature Coverage

| Control | Function(s) | Keycloak Admin API |
|---|---|---|
| Create Realms | `realm_present`, `realm_absent` | `POST/GET/PUT/DELETE admin/realms[/{realm}]` |
| Password Policy | `realm_present` (`password_policy`) | `PUT admin/realms/{realm}` -> `passwordPolicy` |
| Brute Force Detection | `realm_present` (`brute_force_protected`, `failure_factor`, `wait_increment_seconds`, `max_failure_wait_seconds`, `max_delta_time_seconds`, `quick_login_check_milli_seconds`, `minimum_quick_login_wait_seconds`) | `PUT admin/realms/{realm}` |
| Token & Session Timeouts | `realm_present` (`access_token_lifespan`, `sso_session_idle_timeout`, `sso_session_max_lifespan`, `client_session_idle_timeout`, `client_session_max_lifespan`, `offline_session_idle_timeout`) | `PUT admin/realms/{realm}` |
| SSL Required | `realm_present` (`ssl_required`) | `PUT admin/realms/{realm}` -> `sslRequired` |
| Login settings | `realm_present` (`remember_me`, `verify_email`, `login_with_email_allowed`, `duplicate_emails_allowed`, `reset_password_allowed`, `edit_username_allowed`, `registration_allowed`, `registration_email_as_username`) | `PUT admin/realms/{realm}` |
| Themes | `realm_present` (`login_theme`, `account_theme`, `admin_theme`, `email_theme`) | `PUT admin/realms/{realm}` |
| Events / Admin Events | `events_config_present` | `GET/PUT admin/realms/{realm}/events/config` |
| Required Actions | `required_action_present` | `POST admin/realms/{realm}/authentication/register-required-action`, `GET/PUT .../authentication/required-actions/{alias}` |
| Authentication Flows | `authentication_flow_present`, `authentication_flow_absent`, `authentication_execution_present` | Full CRUD under `admin/realms/{realm}/authentication/flows` |
| Clients | `client_present`, `client_absent` | Full CRUD under `admin/realms/{realm}/clients` |
| User Federation (OpenLDAP) | `user_federation_present`, `user_federation_absent` | `admin/realms/{realm}/components` (LDAP provider) |

Every `*_present` function builds a desired-state dict from its convenience kwargs, checks the current representation first (idempotent - a no-op run reports `updated: False`), and accepts an optional full `spec` dict that is merged over (and wins conflicts with) the built dict - the same override pattern used by `kinetic-rook.py`.

## Usage Examples

### Realm with password policy, brute force protection, and session timeouts

```yaml
myrealm:
  keycloak.realm_present:
    - password_policy: "length(12) and upperCase(1) and lowerCase(1) and digits(1) and specialChars(1)"
    - brute_force_protected: true
    - failure_factor: 5
    - wait_increment_seconds: 60
    - access_token_lifespan: 300
    - sso_session_idle_timeout: 1800
    - sso_session_max_lifespan: 36000
    - ssl_required: "external"
    - remember_me: true
    - verify_email: true
    - login_theme: keycloak
    - namespace: keycloak
    - secret_name: keycloak-admin
```

### Events config

```yaml
myrealm_events:
  keycloak.events_config_present:
    - realm: myrealm
    - events_enabled: true
    - events_listeners:
      - jboss-logging
    - admin_events_enabled: true
    - admin_events_details_enabled: true
```

### Required action (e.g. enforce TOTP)

```yaml
myrealm_totp_required:
  keycloak.required_action_present:
    - realm: myrealm
    - provider_id: CONFIGURE_TOTP
    - enabled: true
    - default_action: false
```

### Authentication flow + execution

```yaml
my_browser_flow:
  keycloak.authentication_flow_present:
    - realm: myrealm
    - alias: my-browser-flow
    - description: Custom browser flow
    - provider_id: basic-flow
    - top_level: true

my_browser_flow_otp:
  keycloak.authentication_execution_present:
    - realm: myrealm
    - flow_alias: my-browser-flow
    - provider_id: auth-otp-form
    - requirement: REQUIRED
    - require:
      - keycloak: my_browser_flow
```

### Client

```yaml
my-app:
  keycloak.client_present:
    - realm: myrealm
    # client_id defaults to the state id ("my-app") if not given
    - client_name: My App
    - public_client: false
    - standard_flow_enabled: true
    - direct_access_grants_enabled: false
    - redirect_uris:
      - https://app.example.com/*
    - web_origins:
      - https://app.example.com
```

### User federation (OpenLDAP)

```yaml
corp_ldap:
  keycloak.user_federation_present:
    - realm: myrealm
    - provider_id: ldap
    - config:
        connectionUrl: ldaps://ldap.example.com:636
        usersDn: ou=users,dc=example,dc=com
        bindDn: cn=admin,dc=example,dc=com
        bindCredential: "{{ pillar['ldap']['bind_password'] }}"
        userObjectClasses: "inetOrgPerson, organizationalPerson"
        vendor: other
        editMode: READ_ONLY
        usernameLDAPAttribute: uid
        rdnLDAPAttribute: uid
        uuidLDAPAttribute: entryUUID
        syncRegistrations: "false"
        pagination: "true"
```

## Notes

- `client_present`/`client_absent` use Keycloak's `clientId` (the human-readable identifier), not the internal UUID `id` used in REST paths once the client exists; the internal id is looked up automatically.
- Keycloak never returns a confidential client's `secret` on GET, so `secret` is excluded from the idempotency comparison in `client_present` but is still sent on create/update when provided.
- `authentication_execution_present` manages an execution's `requirement` (DISABLED/ALTERNATIVE/REQUIRED/CONDITIONAL) but does not manage execution ordering/priority (raise/lower) - that is out of scope for now.
- LDAP (and other component) `config` values must be `List[str]` per the Keycloak component representation; `user_federation_present` normalizes scalar values automatically.
- The connection kwarg for the admin login client was named `admin_client_id`/`admin_client_secret` (rather than bare `client_id`/`client_secret`) specifically to avoid colliding with `client_present`'s own `client_id` parameter, which refers to the Keycloak client being managed.

Last updated: July 2025
