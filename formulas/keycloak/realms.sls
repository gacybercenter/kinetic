
{% set kc = pillar.get('res-k8s', {}).get('keycloak', {}) %}
{% set conn = kc.get('connection', {}) %}
{% set keycloak_addr = conn.get('keycloak_addr', 'k8s://keycloak/keycloak-service:8443') %}
{% set kc_namespace = conn.get('namespace', 'keycloak') %}
{% set kc_secret_name = conn.get('secret_name', 'keycloak-admin') %}
{% set kc_verify = conn.get('verify', False) %}

{% macro kc_conn(addr, ns, secret, verify) %}
    - keycloak_addr: {{ addr }}
    - namespace: {{ ns }}
    - secret_name: {{ secret }}
    - verify: {{ verify }}
{%- endmacro %}

{% set realms = pillar.get('ldap', {}).get('realms', {}) %}
{% for realm_name, realm in realms.items() %}

# --- Realm: {{ realm_name }} ---

kc_{{ realm_name }}_realm:
  keycloak.realm_present:
    - name: {{ realm_name }}
    - enabled: {{ realm.get('enabled', True) }}
{%- if realm.get('password_policy') is not none %}
    - password_policy: {{ realm.get('password_policy') | yaml_dquote }}
{%- endif %}
{%- if realm.get('brute_force_protected') is not none %}
    - brute_force_protected: {{ realm.get('brute_force_protected') }}
{%- endif %}
{%- if realm.get('failure_factor') is not none %}
    - failure_factor: {{ realm.get('failure_factor') }}
{%- endif %}
{%- if realm.get('wait_increment_seconds') is not none %}
    - wait_increment_seconds: {{ realm.get('wait_increment_seconds') }}
{%- endif %}
{%- if realm.get('max_failure_wait_seconds') is not none %}
    - max_failure_wait_seconds: {{ realm.get('max_failure_wait_seconds') }}
{%- endif %}
{%- if realm.get('max_delta_time_seconds') is not none %}
    - max_delta_time_seconds: {{ realm.get('max_delta_time_seconds') }}
{%- endif %}
{%- if realm.get('quick_login_check_milli_seconds') is not none %}
    - quick_login_check_milli_seconds: {{ realm.get('quick_login_check_milli_seconds') }}
{%- endif %}
{%- if realm.get('minimum_quick_login_wait_seconds') is not none %}
    - minimum_quick_login_wait_seconds: {{ realm.get('minimum_quick_login_wait_seconds') }}
{%- endif %}
{%- if realm.get('access_token_lifespan') is not none %}
    - access_token_lifespan: {{ realm.get('access_token_lifespan') }}
{%- endif %}
{%- if realm.get('sso_session_idle_timeout') is not none %}
    - sso_session_idle_timeout: {{ realm.get('sso_session_idle_timeout') }}
{%- endif %}
{%- if realm.get('sso_session_max_lifespan') is not none %}
    - sso_session_max_lifespan: {{ realm.get('sso_session_max_lifespan') }}
{%- endif %}
{%- if realm.get('client_session_idle_timeout') is not none %}
    - client_session_idle_timeout: {{ realm.get('client_session_idle_timeout') }}
{%- endif %}
{%- if realm.get('client_session_max_lifespan') is not none %}
    - client_session_max_lifespan: {{ realm.get('client_session_max_lifespan') }}
{%- endif %}
{%- if realm.get('offline_session_idle_timeout') is not none %}
    - offline_session_idle_timeout: {{ realm.get('offline_session_idle_timeout') }}
{%- endif %}
{%- if realm.get('ssl_required') is not none %}
    - ssl_required: {{ realm.get('ssl_required') | yaml_dquote }}
{%- endif %}
{%- if realm.get('remember_me') is not none %}
    - remember_me: {{ realm.get('remember_me') }}
{%- endif %}
{%- if realm.get('verify_email') is not none %}
    - verify_email: {{ realm.get('verify_email') }}
{%- endif %}
{%- if realm.get('login_with_email_allowed') is not none %}
    - login_with_email_allowed: {{ realm.get('login_with_email_allowed') }}
{%- endif %}
{%- if realm.get('duplicate_emails_allowed') is not none %}
    - duplicate_emails_allowed: {{ realm.get('duplicate_emails_allowed') }}
{%- endif %}
{%- if realm.get('reset_password_allowed') is not none %}
    - reset_password_allowed: {{ realm.get('reset_password_allowed') }}
{%- endif %}
{%- if realm.get('edit_username_allowed') is not none %}
    - edit_username_allowed: {{ realm.get('edit_username_allowed') }}
{%- endif %}
{%- if realm.get('registration_allowed') is not none %}
    - registration_allowed: {{ realm.get('registration_allowed') }}
{%- endif %}
{%- if realm.get('registration_email_as_username') is not none %}
    - registration_email_as_username: {{ realm.get('registration_email_as_username') }}
{%- endif %}
{%- if realm.get('login_theme') is not none %}
    - login_theme: {{ realm.get('login_theme') }}
{%- endif %}
{%- if realm.get('account_theme') is not none %}
    - account_theme: {{ realm.get('account_theme') }}
{%- endif %}
{%- if realm.get('admin_theme') is not none %}
    - admin_theme: {{ realm.get('admin_theme') }}
{%- endif %}
{%- if realm.get('email_theme') is not none %}
    - email_theme: {{ realm.get('email_theme') }}
{%- endif %}
{%- if realm.get('smtp_server') is not none %}
    - smtp_server: {{ realm.get('smtp_server') | tojson }}
{%- endif %}
{%- if realm.get('attributes') is not none %}
    - attributes: {{ realm.get('attributes') | tojson }}
{%- endif %}
{%- if realm.get('spec') is not none %}
    - spec: {{ realm.get('spec') | tojson }}
{%- endif %}
{{ kc_conn(keycloak_addr, kc_namespace, kc_secret_name, kc_verify) }}

{# --- Events / Admin Events --- #}
{% if realm.get('events') %}
{% set events = realm.get('events') %}
kc_{{ realm_name }}_events:
  keycloak.events_config_present:
    - name: {{ realm_name }}
{%- if events.get('events_enabled') is not none %}
    - events_enabled: {{ events.get('events_enabled') }}
{%- endif %}
{%- if events.get('events_listeners') is not none %}
    - events_listeners: {{ events.get('events_listeners') | tojson }}
{%- endif %}
{%- if events.get('enabled_event_types') is not none %}
    - enabled_event_types: {{ events.get('enabled_event_types') | tojson }}
{%- endif %}
{%- if events.get('events_expiration') is not none %}
    - events_expiration: {{ events.get('events_expiration') }}
{%- endif %}
{%- if events.get('admin_events_enabled') is not none %}
    - admin_events_enabled: {{ events.get('admin_events_enabled') }}
{%- endif %}
{%- if events.get('admin_events_details_enabled') is not none %}
    - admin_events_details_enabled: {{ events.get('admin_events_details_enabled') }}
{%- endif %}
{{ kc_conn(keycloak_addr, kc_namespace, kc_secret_name, kc_verify) }}
    - require:
      - keycloak: kc_{{ realm_name }}_realm
{% endif %}

{# --- Required Actions --- #}
{% for ra in realm.get('required_actions', []) %}
kc_{{ realm_name }}_required_action_{{ ra['provider_id'] }}:
  keycloak.required_action_present:
    - realm: {{ realm_name }}
    - provider_id: {{ ra['provider_id'] }}
{%- if ra.get('alias') is not none %}
    - alias: {{ ra.get('alias') }}
{%- endif %}
{%- if ra.get('display_name') is not none %}
    - display_name: {{ ra.get('display_name') | yaml_dquote }}
{%- endif %}
    - enabled: {{ ra.get('enabled', True) }}
    - default_action: {{ ra.get('default_action', False) }}
{%- if ra.get('priority') is not none %}
    - priority: {{ ra.get('priority') }}
{%- endif %}
{%- if ra.get('config') is not none %}
    - config: {{ ra.get('config') | tojson }}
{%- endif %}
{{ kc_conn(keycloak_addr, kc_namespace, kc_secret_name, kc_verify) }}
    - require:
      - keycloak: kc_{{ realm_name }}_realm
{% endfor %}

{# --- Authentication Flows + Executions --- #}
{% for flow_key, flow in realm.get('authentication_flows', {}).items() %}
kc_{{ realm_name }}_flow_{{ flow_key }}:
  keycloak.authentication_flow_present:
    - name: {{ flow_key }}
    - realm: {{ realm_name }}
{%- if flow.get('alias') is not none %}
    - alias: {{ flow.get('alias') }}
{%- endif %}
{%- if flow.get('description') is not none %}
    - description: {{ flow.get('description') | yaml_dquote }}
{%- endif %}
    - provider_id: {{ flow.get('provider_id', 'basic-flow') }}
    - top_level: {{ flow.get('top_level', True) }}
    - built_in: {{ flow.get('built_in', False) }}
{{ kc_conn(keycloak_addr, kc_namespace, kc_secret_name, kc_verify) }}
    - require:
      - keycloak: kc_{{ realm_name }}_realm

{% for execution in flow.get('executions', []) %}
kc_{{ realm_name }}_flow_{{ flow_key }}_exec_{{ loop.index }}_{{ execution['provider_id'] }}:
  keycloak.authentication_execution_present:
    - name: {{ flow_key }}-exec-{{ loop.index }}
    - realm: {{ realm_name }}
    - flow_alias: {{ flow.get('alias', flow_key) }}
    - provider_id: {{ execution['provider_id'] }}
    - requirement: {{ execution.get('requirement', 'DISABLED') }}
{%- if execution.get('type') is not none %}
    - type: {{ execution['type'] }}
{%- endif %}
{{ kc_conn(keycloak_addr, kc_namespace, kc_secret_name, kc_verify) }}
    - require:
      - keycloak: kc_{{ realm_name }}_flow_{{ flow_key }}
{% endfor %}
{% endfor %}

{# --- Realm flow bindings (browserFlow, registrationFlow, etc.) - applied
     after all authentication flows/executions exist, since Keycloak
     rejects binding a realm flow field to an alias that doesn't exist yet --- #}
{% if realm.get('browser_flow') is not none or realm.get('registration_flow') is not none or realm.get('direct_grant_flow') is not none or realm.get('reset_credentials_flow') is not none or realm.get('client_authentication_flow') is not none or realm.get('docker_authentication_flow') is not none %}
kc_{{ realm_name }}_flow_bindings:
  keycloak.realm_present:
    - name: {{ realm_name }}
    - enabled: {{ realm.get('enabled', True) }}
{%- if realm.get('browser_flow') is not none %}
    - browser_flow: {{ realm.get('browser_flow') | yaml_dquote }}
{%- endif %}
{%- if realm.get('registration_flow') is not none %}
    - registration_flow: {{ realm.get('registration_flow') | yaml_dquote }}
{%- endif %}
{%- if realm.get('direct_grant_flow') is not none %}
    - direct_grant_flow: {{ realm.get('direct_grant_flow') | yaml_dquote }}
{%- endif %}
{%- if realm.get('reset_credentials_flow') is not none %}
    - reset_credentials_flow: {{ realm.get('reset_credentials_flow') | yaml_dquote }}
{%- endif %}
{%- if realm.get('client_authentication_flow') is not none %}
    - client_authentication_flow: {{ realm.get('client_authentication_flow') | yaml_dquote }}
{%- endif %}
{%- if realm.get('docker_authentication_flow') is not none %}
    - docker_authentication_flow: {{ realm.get('docker_authentication_flow') | yaml_dquote }}
{%- endif %}
{{ kc_conn(keycloak_addr, kc_namespace, kc_secret_name, kc_verify) }}
    - require:
      - keycloak: kc_{{ realm_name }}_realm
{%- for flow_key, flow in realm.get('authentication_flows', {}).items() %}
      - keycloak: kc_{{ realm_name }}_flow_{{ flow_key }}
{%- endfor %}
{% endif %}

{# --- Clients --- #}
{% for client_key, client in realm.get('clients', {}).items() %}
kc_{{ realm_name }}_client_{{ client_key }}:
  keycloak.client_present:
    - name: {{ client_key }}
    - realm: {{ realm_name }}
{%- if client.get('client_id') is not none %}
    - client_id: {{ client.get('client_id') }}
{%- endif %}
{%- if client.get('client_name') is not none %}
    - client_name: {{ client.get('client_name') | yaml_dquote }}
{%- endif %}
{%- if client.get('description') is not none %}
    - description: {{ client.get('description') | yaml_dquote }}
{%- endif %}
    - enabled: {{ client.get('enabled', True) }}
    - protocol: {{ client.get('protocol', 'openid-connect') }}
    - public_client: {{ client.get('public_client', False) }}
    - standard_flow_enabled: {{ client.get('standard_flow_enabled', True) }}
    - direct_access_grants_enabled: {{ client.get('direct_access_grants_enabled', True) }}
    - service_accounts_enabled: {{ client.get('service_accounts_enabled', False) }}
    - authorization_services_enabled: {{ client.get('authorization_services_enabled', False) }}
{%- if client.get('redirect_uris') is not none %}
    - redirect_uris: {{ client.get('redirect_uris') | tojson }}
{%- endif %}
{%- if client.get('web_origins') is not none %}
    - web_origins: {{ client.get('web_origins') | tojson }}
{%- endif %}
{%- if client.get('root_url') is not none %}
    - root_url: {{ client.get('root_url') | yaml_dquote }}
{%- endif %}
{%- if client.get('base_url') is not none %}
    - base_url: {{ client.get('base_url') | yaml_dquote }}
{%- endif %}
    - client_authenticator_type: {{ client.get('client_authenticator_type', 'client-secret') }}
{%- if client.get('secret') is not none %}
    - secret: {{ client.get('secret') | yaml_dquote }}
{%- endif %}
{%- if client.get('pkce_code_challenge_method') is not none %}
    - pkce_code_challenge_method: {{ client.get('pkce_code_challenge_method') | yaml_dquote }}
{%- endif %}
{%- if client.get('attributes') is not none %}
    - attributes: {{ client.get('attributes') | tojson }}
{%- endif %}
{%- if client.get('spec') is not none %}
    - spec: {{ client.get('spec') | tojson }}
{%- endif %}
{{ kc_conn(keycloak_addr, kc_namespace, kc_secret_name, kc_verify) }}
    - require:
      - keycloak: kc_{{ realm_name }}_realm

{# --- Default client scopes (additive; does not remove existing ones) --- #}
{% for scope_name in client.get('default_client_scopes', []) %}
kc_{{ realm_name }}_client_{{ client_key }}_default_scope_{{ scope_name }}:
  keycloak.client_default_scope_present:
    - name: {{ client_key }}
    - realm: {{ realm_name }}
    - scope_name: {{ scope_name }}
{%- if client.get('client_id') is not none %}
    - client_id: {{ client.get('client_id') }}
{%- endif %}
{{ kc_conn(keycloak_addr, kc_namespace, kc_secret_name, kc_verify) }}
    - require:
      - keycloak: kc_{{ realm_name }}_client_{{ client_key }}
{% endfor %}
{% endfor %}

{# --- User Federation (e.g. OpenLDAP) --- #}
{% for fed_key, fed in realm.get('user_federation', {}).items() %}
kc_{{ realm_name }}_federation_{{ fed_key }}:
  keycloak.user_federation_present:
    - name: {{ fed_key }}
    - realm: {{ realm_name }}
    - provider_id: {{ fed.get('provider_id', 'ldap') }}
    - provider_type: {{ fed.get('provider_type', 'org.keycloak.storage.UserStorageProvider') }}
{%- if fed.get('parent_id') is not none %}
    - parent_id: {{ fed.get('parent_id') }}
{%- endif %}
{%- if fed.get('start_tls') is not none %}
    - start_tls: {{ fed.get('start_tls') }}
{%- endif %}
{%- if fed.get('use_truststore_spi') is not none %}
    - use_truststore_spi: {{ fed.get('use_truststore_spi') }}
{%- endif %}
{%- if fed.get('config') is not none %}
    - config: {{ fed.get('config') | tojson }}
{%- endif %}
{{ kc_conn(keycloak_addr, kc_namespace, kc_secret_name, kc_verify) }}
    - require:
      - keycloak: kc_{{ realm_name }}_realm

{# --- LDAP Mappers (e.g. group-ldap-mapper) for this federation provider --- #}
{% for mapper_key, mapper in fed.get('mappers', {}).items() %}
kc_{{ realm_name }}_federation_{{ fed_key }}_mapper_{{ mapper_key }}:
  keycloak.ldap_mapper_present:
    - name: {{ mapper_key }}
    - realm: {{ realm_name }}
    - federation_name: {{ fed_key }}
    - provider_id: {{ mapper['provider_id'] }}
    - provider_type: {{ mapper.get('provider_type', 'org.keycloak.storage.ldap.mappers.LDAPStorageMapper') }}
{%- if mapper.get('config') is not none %}
    - config: {{ mapper.get('config') | tojson }}
{%- endif %}
{{ kc_conn(keycloak_addr, kc_namespace, kc_secret_name, kc_verify) }}
    - require:
      - keycloak: kc_{{ realm_name }}_federation_{{ fed_key }}
{% endfor %}
{% endfor %}

{% endfor %}
