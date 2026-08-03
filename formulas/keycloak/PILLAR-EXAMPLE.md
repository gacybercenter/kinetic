# Keycloak Pillar Example

The `formulas/keycloak/configure` state is entirely pillar-driven: it reads
`res-k8s:keycloak:realms` and, for every realm defined there, builds the
`keycloak.*` states (from `_states/keycloak.py`, backed by the
`kinetic_keycloak` execution module - see `docs/kinetic-keycloak.md`) needed to
configure that realm's password policy, brute force detection, token/session
timeouts, events, required actions, authentication flows, clients, and user
federation.

Realms are applied in this order per realm: realm -> events -> required
actions -> authentication flows (and their executions) -> clients -> user
federation. Everything except the realm itself `require`s the realm state.

## Connection settings

By default, the admin token is obtained using the `keycloak-admin` Secret in
the `keycloak` namespace, proxied through the Kubernetes API
(`k8s://keycloak/keycloak-service:8443`) - see "Authentication" in
`docs/kinetic-keycloak.md`. Override these under
`res-k8s:keycloak:connection` if needed:

```yaml
res-k8s:
  keycloak:
    connection:
      keycloak_addr: k8s://keycloak/keycloak-service:8443
      namespace: keycloak
      secret_name: keycloak-admin
      verify: false
```

## Full realm example

```yaml
res-k8s:
  keycloak:
    # Used by formulas/keycloak/install.sls for the Helm release
    chart_name: codecentric/keycloakx
    values: {}

    connection:
      namespace: keycloak
      secret_name: keycloak-admin

    realms:
      myrealm:
        enabled: true

        # --- Password Policy ---
        password_policy: "length(12) and upperCase(1) and lowerCase(1) and digits(1) and specialChars(1)"

        # --- Brute Force Detection ---
        brute_force_protected: true
        failure_factor: 5
        wait_increment_seconds: 60
        max_failure_wait_seconds: 900
        max_delta_time_seconds: 43200
        quick_login_check_milli_seconds: 1000
        minimum_quick_login_wait_seconds: 60

        # --- Token & Session Timeouts ---
        access_token_lifespan: 300
        sso_session_idle_timeout: 1800
        sso_session_max_lifespan: 36000
        client_session_idle_timeout: 0
        client_session_max_lifespan: 0
        offline_session_idle_timeout: 2592000

        # --- SSL Required ---
        ssl_required: external

        # --- Login settings ---
        remember_me: true
        verify_email: true
        login_with_email_allowed: true
        duplicate_emails_allowed: false
        reset_password_allowed: true
        edit_username_allowed: false
        registration_allowed: false
        registration_email_as_username: false

        # --- Themes ---
        login_theme: keycloak
        account_theme: keycloak
        admin_theme: keycloak
        email_theme: keycloak

        # --- Events / Admin Events ---
        events:
          events_enabled: true
          events_listeners:
            - jboss-logging
          admin_events_enabled: true
          admin_events_details_enabled: true
          events_expiration: 604800

        # --- Required Actions ---
        required_actions:
          - provider_id: CONFIGURE_TOTP
            enabled: true
            default_action: false
          - provider_id: UPDATE_PASSWORD
            enabled: true
            default_action: false
          - provider_id: VERIFY_EMAIL
            enabled: true
            default_action: false

        # --- Authentication Flows (with executions) ---
        authentication_flows:
          my-browser-flow:
            description: Custom browser flow with OTP
            provider_id: basic-flow
            top_level: true
            executions:
              - provider_id: auth-username-password-form
                requirement: REQUIRED
              - provider_id: auth-otp-form
                requirement: REQUIRED

        # --- Clients ---
        clients:
          my-app:
            client_name: My Application
            public_client: false
            standard_flow_enabled: true
            direct_access_grants_enabled: false
            redirect_uris:
              - https://app.example.com/*
            web_origins:
              - https://app.example.com
          my-service:
            client_name: My Service Account Client
            public_client: false
            standard_flow_enabled: false
            direct_access_grants_enabled: false
            service_accounts_enabled: true
            client_authenticator_type: client-secret
            secret: {{ pillar['keycloak-secrets']['my-service-client-secret'] }}

        # --- User Federation (OpenLDAP) ---
        user_federation:
          corp-ldap:
            provider_id: ldap
            config:
              connectionUrl: ldaps://ldap.example.com:636
              usersDn: ou=users,dc=example,dc=com
              bindDn: cn=admin,dc=example,dc=com
              bindCredential: {{ pillar['ldap']['bind_password'] }}
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

- Every key under a realm is optional; omit any control you don't want to
  manage and the corresponding field is left untouched.
- `authentication_flows` and `clients` and `user_federation` are keyed dicts
  (the key becomes part of the Salt state ID, and doubles as the flow
  alias / client_id / component name unless overridden with `alias:`,
  `client_id:`, or `name:` respectively - not applicable for federation,
  whose key is always the component name).
- `required_actions` is a list because Keycloak allows several required
  actions per realm and order doesn't otherwise matter for identification
  (each is keyed by `provider_id`).
- Any field not covered by the convenience kwargs above can still be set via
  a raw `spec:` dict on `realms.<realm>.spec` or `clients.<client>.spec`,
  which is merged over (and wins conflicts with) the built dict - see
  `docs/kinetic-keycloak.md`.
- Secrets (LDAP bind password, client secrets) should come from other pillar
  data (e.g. an encrypted pillar or vault-backed source) rather than being
  hardcoded here.

## Applying

```bash
salt '*' state.apply formulas.keycloak.configure
```
