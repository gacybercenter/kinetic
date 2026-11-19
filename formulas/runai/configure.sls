include:
  - /formulas/runai/install

{# Same NGC login as the helm repo: username $oauthtoken, password from
   res-k8s:gpu:runai:ngc_api_key. The secret is the dockerconfigjson
   kubelet uses to pull from nvcr.io. Equivalent to:
     kubectl create secret docker-registry runai-reg-creds -n runai \
       --docker-server=nvcr.io \
       --docker-username='$oauthtoken' \
       --docker-password=<NGC_API_KEY> \
       --docker-email='$oauthtoken'
   Override namespace / secret name / registry under res-k8s:gpu:runai. #}
{% set runai = pillar.get('res-k8s', {}).get('gpu', {}).get('runai', {}) %}
{% set runai_ns = runai.get('namespace', 'runai') %}
{% set pull_secret = runai.get('pull_secret', 'runai-reg-creds') %}
{% set registry = runai.get('registry', 'nvcr.io') %}
{% set ngc_user = '$oauthtoken' %}
{% set ngc_key = (runai.get('ngc_api_key') or '') | trim %}
{% set admin = runai.get('admin_account') or {} %}
{% set admin_name = (admin.get('name') or '') | trim %}
{% set admin_pass = admin.get('pass') or '' %}
{% set admin_secret = admin.get('secret_name', 'runai-admin') %}
{# Control plane is a separate release from the cluster chart, installed
   in the same runai namespace. Values are the chart's own values.yaml
   shape, including tenantsManager.config.adminUsername/adminPassword. #}
{% set cp_ns = runai.get('controlplane_namespace', runai_ns) %}
{% set cp_chart = runai.get('controlplane_chart', 'runai/control-plane') %}
{% set cp_release = runai.get('controlplane_release', 'runai-backend') %}
{% set cp_version = runai.get('controlplane_version') %}
{% set cp_values = (runai.get('values') or {}).get('controlplane') %}

ensure_runai_repo:
  k8s_helm.helm_repo_present:
    - repo_name: runai
    - repo_url: https://helm.ngc.nvidia.com/nvidia/runai
    - username: "$oauthtoken"
    - password_pillar: res-k8s:gpu:runai:ngc_api_key

ensure_runai_namespace:
  k8s.namespace_present:
    - namespace: {{ runai_ns }}

{% if not ngc_key %}
ensure_runai_pull_secret:
  test.fail_without_changes:
    - name: {{ pull_secret }}
    - comment: "res-k8s:gpu:runai:ngc_api_key is missing or empty. The nvcr.io pull secret needs the same NGC API key as the helm repo."
{% else %}
{# containerd looks up nvcr.io; some NGC examples key the secret as
   https://nvcr.io. Store both unless registry is overridden. #}
{% set registries = [registry] %}
{% if registry == 'nvcr.io' %}
{% do registries.append('https://nvcr.io') %}
{% endif %}
{% set auths = {} %}
{% for server in registries %}
{% do auths.update({server: {
  'username': ngc_user,
  'password': ngc_key,
  'email': ngc_user,
  'auth': (ngc_user ~ ':' ~ ngc_key) | base64_encode,
}}) %}
{% endfor %}
{% set dockerconfig = {'auths': auths} %}
ensure_runai_pull_secret:
  k8s.secret_present:
    - secret_name: {{ pull_secret }}
    - namespace: {{ runai_ns }}
    - secret_type: kubernetes.io/dockerconfigjson
    - data:
        .dockerconfigjson: {{ dockerconfig | tojson | yaml_dquote }}
    - require:
      - k8s: ensure_runai_namespace
{% endif %}

{# Control-plane login. Pillar is GPG-encrypted; the renderer decrypts it
   before this state renders. Keys match the keycloak-admin secret. #}
{% if not admin_name or not (admin_pass | trim) %}
ensure_runai_admin_secret:
  test.fail_without_changes:
    - name: {{ admin_secret }}
    - comment: "res-k8s:gpu:runai:admin_account needs name and pass."
{% else %}
ensure_runai_admin_secret:
  k8s.secret_present:
    - secret_name: {{ admin_secret }}
    - namespace: {{ runai_ns }}
    - secret_type: Opaque
    - data:
        username: {{ admin_name | trim | yaml_dquote }}
        password: {{ admin_pass | trim | yaml_dquote }}
    - require:
      - k8s: ensure_runai_namespace
{% endif %}
{% if not cp_values %}
install_runai_backend:
  test.fail_without_changes:
    - name: {{ cp_release }}
    - comment: "res-k8s:gpu:runai:values:controlplane is missing. That dict is passed to helm as the control-plane chart values."
{% else %}
install_runai_backend:
  k8s_helm.helm_release_present:
    - release_name: {{ cp_release }}
    - chart_name: {{ cp_chart | yaml_dquote }}
    - namespace: {{ cp_ns }}
    - pillar_key: res-k8s:gpu:runai:values:controlplane
{%- if cp_version %}
    - version: {{ cp_version | yaml_dquote }}
{%- endif %}
    - wait: false
    - wait_timeout: 900
    - wait_interval: 15
    - require:
      - k8s_helm: ensure_runai_repo
      - k8s: ensure_runai_namespace
      - k8s: ensure_runai_pull_secret
{% endif %}

{# Run:ai's embedded Keycloak brokers into realm rsc as this client.
   provider_metadata_url is the discovery document Run:ai consumes; it is
   not a client field. logout_redirect is post.logout.redirect.uris.
   A public broker must not force PKCE: the identity-provider redirect
   does not send code_challenge unless that IdP is configured for it. #}
{% set oidc = runai.get('oidc_client') or {} %}
{% set broker = oidc.get('runai') or {} %}
{% set kc = pillar.get('res-k8s', {}).get('keycloak', {}) %}
{% set kc_conn = kc.get('connection', {}) %}
{% set kc_realm = broker.get('realm', 'rsc') %}
{% set broker_id = broker.get('client_id', 'runai-broker') %}
{% set logout_uris = broker.get('logout_redirect', broker.get('post_logout_redirect_uris', [])) %}
{% set broker_public = broker.get('public_client', True) %}
{% set broker_secret = (broker.get('secret') or '') | trim %}

{% if not broker %}
runai_keycloak_broker_client:
  test.fail_without_changes:
    - name: runai-broker
    - comment: "res-k8s:gpu:runai:oidc_client:runai is missing."
{% else %}
runai_keycloak_broker_client:
  keycloak.client_present:
    - name: {{ broker_id }}
    - realm: {{ kc_realm }}
    - client_id: {{ broker_id }}
    - client_name: {{ broker.get('client_name', 'Run:ai Broker') | yaml_dquote }}
    - description: "Run:ai identity broker client"
    - enabled: {{ broker.get('enabled', True) }}
    - protocol: openid-connect
    - public_client: {{ broker_public }}
    - standard_flow_enabled: {{ broker.get('standard_flow_enabled', True) }}
    - direct_access_grants_enabled: {{ broker.get('direct_access_grants_enabled', False) }}
    - service_accounts_enabled: {{ broker.get('service_accounts_enabled', False) }}
    - authorization_services_enabled: {{ broker.get('authorization_services_enabled', False) }}
{%- if broker.get('redirect_uris') %}
    - redirect_uris: {{ broker.get('redirect_uris') | tojson }}
{%- endif %}
{%- if logout_uris %}
    - attributes:
        post.logout.redirect.uris: {{ logout_uris | join('##') | yaml_dquote }}
{%- endif %}
{%- if broker.get('pkce_code_challenge_method') is not none %}
    - pkce_code_challenge_method: {{ broker.get('pkce_code_challenge_method') | yaml_dquote }}
{%- elif broker_public %}
    - pkce_code_challenge_method: ""
{%- endif %}
{# publicClient and secret together is unusual. Run:ai's broker
   still sends the client secret, so set it even when the client is public. #}
{%- if broker_secret %}
    - secret: {{ broker.get('secret') | yaml_dquote }}
{%- endif %}
    - keycloak_addr: {{ kc_conn.get('keycloak_addr', 'k8s://keycloak/keycloak-service:8443') }}
    - namespace: {{ kc_conn.get('namespace', 'keycloak') }}
    - secret_name: {{ kc_conn.get('secret_name', 'keycloak-admin') }}
    - verify: {{ kc_conn.get('verify', False) }}

{% for scope_name in broker.get('default_client_scopes', []) %}
runai_keycloak_broker_client_default_scope_{{ scope_name }}:
  keycloak.client_default_scope_present:
    - name: {{ broker_id }}
    - realm: {{ kc_realm }}
    - scope_name: {{ scope_name }}
    - client_id: {{ broker_id }}
    - keycloak_addr: {{ kc_conn.get('keycloak_addr', 'k8s://keycloak/keycloak-service:8443') }}
    - namespace: {{ kc_conn.get('namespace', 'keycloak') }}
    - secret_name: {{ kc_conn.get('secret_name', 'keycloak-admin') }}
    - verify: {{ kc_conn.get('verify', False) }}
    - require:
      - keycloak: runai_keycloak_broker_client
{% endfor %}
{% endif %}

{# IdP on the Keycloak embedded in Run:ai, brokering to realm rsc.
   That Keycloak still serves /auth, so api_prefix defaults to auth.
   The chart services are keycloak-http (port 80) and keycloak-headless
   (port 8080), both HTTP. connection.secret_name is the embedded
   Keycloak master admin secret, not runai-admin. #}
{% set idp = oidc.get('runai_idp') or {} %}
{% set idp_conn = idp.get('connection') or {} %}
{% set idp_alias = idp.get('alias', 'rsc-oidc') %}
{% set idp_auth = idp.get('auth_url', '') %}
{% set idp_issuer = idp_auth.replace('/protocol/openid-connect/auth', '').rstrip('/') %}
{% set idp_userinfo_given = idp.get('user_info_url', '') %}
{% set idp_userinfo = idp_issuer ~ '/protocol/openid-connect/userinfo' if idp_userinfo_given.endswith('/logout') else idp_userinfo_given %}
{% set idp_logout = idp_userinfo_given if idp_userinfo_given.endswith('/logout') else idp.get('logout_url', idp_issuer ~ '/protocol/openid-connect/logout') %}
{% set idp_config = {
  'clientId': broker_id,
  'clientSecret': broker.get('secret') or '',
  'clientAuthMethod': 'client_secret_post',
  'defaultScope': idp.get('default_scopes', 'openid profile email groups'),
  'syncMode': idp.get('sync_mode', 'IMPORT'),
  'authorizationUrl': idp_auth,
  'tokenUrl': idp.get('token_url', ''),
  'userInfoUrl': idp_userinfo,
  'logoutUrl': idp_logout,
  'issuer': idp.get('issuer', idp_issuer),
  'validateSignature': 'true' if idp.get('valid_sigs', True) else 'false',
  'useJwksUrl': 'true' if idp.get('use_jwks_url', True) else 'false',
  'jwksUrl': idp.get('jwks_url', idp_issuer ~ '/protocol/openid-connect/certs'),
  'pkceEnabled': 'false',
} %}

{% if not idp %}
{% elif not idp_conn.get('secret_name') or not broker_secret %}
runai_keycloak_idp:
  test.fail_without_changes:
    - name: {{ idp_alias }}
    - comment: "res-k8s:gpu:runai:oidc_client:runai_idp.connection.secret_name must be the embedded Keycloak admin secret, and oidc_client.runai.secret is the broker client secret sent as clientSecret."
{% else %}
runai_keycloak_idp:
  keycloak.identity_provider_present:
    - name: {{ idp_alias }}
    - realm: {{ idp_conn.get('realm', 'runai') }}
    - alias: {{ idp_alias }}
    - provider_id: oidc
    - display_name: {{ idp.get('display_name', 'RSC Login') | yaml_dquote }}
    - enabled: {{ idp.get('enabled', True) }}
    - trust_email: {{ idp.get('trust_email', True) }}
    - first_broker_login_flow: {{ idp.get('first_login_flow', 'first broker login') | yaml_dquote }}
    - config: {{ idp_config | tojson }}
    - keycloak_addr: {{ idp_conn.get('keycloak_addr', 'k8s://' ~ runai_ns ~ '/http:keycloak-http:80') | yaml_dquote }}
    - namespace: {{ idp_conn.get('namespace', runai_ns) }}
    - secret_name: {{ idp_conn.get('secret_name') }}
    - verify: {{ idp_conn.get('verify', False) }}
    - api_prefix: {{ idp_conn.get('api_prefix', 'auth') }}
    - require:
      - keycloak: runai_keycloak_broker_client
{% endif %}
