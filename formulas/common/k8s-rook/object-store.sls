{# CephObjectStore with RGW STS (and IAM, for OIDC provider + roles).
   Pillar:
     res-k8s:rook:object_store:
       name: my-store
       gateway_instances: 2
       erasure_coded:
         data_chunks: 2
         coding_chunks: 1
       sts_key: "<same 16+ char key on every RGW>"
         # ceph-authtool --gen-print-key
#}
{% set store = pillar['res-k8s']['rook']['object_store'] %}
{% set ec = store.get('erasure_coded', {'data_chunks': 2, 'coding_chunks': 1}) %}
{% set store_name = store.get('name', 'my-store') %}
{% set rook_ns = pillar['res-k8s']['rook'].get('namespace', 'rook-ceph') %}
{% set object_hostnames = [] %}
{% for h in store.get('hosts', []) %}
{% if h is mapping %}
{% do object_hostnames.append(h['host']) %}
{% else %}
{% do object_hostnames.append(h) %}
{% endif %}
{% endfor %}
{% set gateway_name = store.get('gateway_name', 'external') %}
{% set gateway_namespace = store.get('gateway_namespace', 'ingress') %}
{% set gateway_section = store.get('gateway_section', 'websecure-ext') %}
{% set kc = pillar.get('res-k8s', {}).get('keycloak', {}) %}
{% set kc_conn = kc.get('connection', {}) %}
{% set keycloak_addr = kc_conn.get('keycloak_addr', 'https://keycloak.rsc.gacyberrange.org') %}
{% set kc_admin = kc.get('values', {}).get('keycloak', {}) %}
{% set kc_client = store.get('keycloak', {}) %}
{% set oidc_issuer = pillar.get('res-k8s', {}).get('oidc-issuer') or kc.get('oidc-issuer') or (keycloak_addr.rstrip('/') ~ '/realms/' ~ kc_client.get('realm', 'rsc')) %}
{% set oidc = store.get('oidc') or ({
  'name': 'keycloak',
  'issuer_url': oidc_issuer,
  'client_id': kc_client.get('client_id', store_name),
  'client_secret': kc_client.get('secret'),
  'role': store_name ~ '-oidc-role',
  'buckets': store.get('buckets', []),
} if kc_client.get('secret') and oidc_issuer.startswith('http') else {}) %}

rook_ceph_object_store:
  rook.ceph_object_store_present:
    - name: {{ store_name }}
    - namespace: {{ rook_ns }}
    - replicas: {{ store.get('metadata_replicas', 3) }}
    - port: {{ store.get('port', 80) }}
    - ssl_enabled: false
    - gateway_instances: {{ store.get('gateway_instances', 2) }}
    - enable_swift_api: false
    - enable_s3_api: true
    - preserve_pools_on_delete: true
    - erasure_coded: {{ ec | tojson }}
    - enable_sts: true
    - sts_key: {{ store['sts_key'] | yaml_dquote }}
    - enable_apis: {{ store.get('enable_apis', ['s3', 's3website', 'sts', 'iam', 'notifications']) | tojson }}
    - rgw_config:
        rgw_s3_auth_use_sts: "true"
        rgw_sts_key: {{ store['sts_key'] | yaml_dquote }}

{% if oidc %}
{% set oidc_name = oidc.get('name', 'keycloak') %}
{% set oidc_client = oidc.get('client_id', store_name) %}
{% set oidc_role = oidc.get('role', store_name ~ '-oidc-role') %}
object_store_oidc_provider:
  rook.oidc_provider_present:
    - name: {{ oidc_name }}
    - namespace: {{ rook_ns }}
    - issuer_url: {{ oidc['issuer_url'] | yaml_dquote }}
    - client_id: {{ oidc_client | yaml_dquote }}
    - client_secret: {{ oidc['client_secret'] | yaml_dquote }}
    - require:
      - rook: rook_ceph_object_store

object_store_oidc_role:
  rook.rgw_role_present:
    - name: {{ oidc_role }}
    - namespace: {{ rook_ns }}
    - provider_name: {{ oidc_name }}
    - audience: {{ oidc_client | yaml_dquote }}
    - audience_claim: {{ oidc.get('audience_claim', 'aud') | yaml_dquote }}
    - require:
      - rook: object_store_oidc_provider

{% if oidc.get('buckets') %}
object_store_oidc_role_policy:
  rook.rgw_role_policy_present:
    - name: {{ oidc.get('policy_name', store_name ~ '-full-access') }}
    - namespace: {{ rook_ns }}
    - role_name: {{ oidc_role }}
    - buckets: {{ oidc['buckets'] | tojson }}
    - require:
      - rook: object_store_oidc_role
{% endif %}
{% endif %}

{% if object_hostnames %}
# TLS terminates on the external Gateway. RGW Service is rook-ceph-rgw-<store>.
object_store_httproute:
  k8s.httproute_present:
    - name: {{ store_name }}-route
    - namespace: {{ rook_ns }}
    - parent_refs:
        - name: {{ gateway_name }}
          namespace: {{ gateway_namespace }}
          sectionName: {{ gateway_section }}
    - hostnames: {{ object_hostnames | tojson }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: rook-ceph-rgw-{{ store_name }}
              port: {{ store.get('port', 80) }}
    - require:
      - rook: rook_ceph_object_store
{% endif %}

{% if kc_client %}
{% set kc_realm = kc_client.get('realm', 'rsc') %}
{% set kc_client_id = kc_client.get('client_id', store_name) %}
{% set redirect_uris = kc_client.get('redirect_uris', []) %}
{% if not redirect_uris %}
{% set redirect_uris = [] %}
{% for host in object_hostnames %}
{% do redirect_uris.append('https://' ~ host ~ '/*') %}
{% endfor %}
{% endif %}
object_store_keycloak_client:
  keycloak.client_present:
    - name: {{ kc_client_id }}
    - realm: {{ kc_realm }}
    - client_id: {{ kc_client_id }}
    - client_name: {{ kc_client.get('client_name', 'RGW ' ~ store_name) }}
    - description: "OIDC client for Ceph object store {{ store_name }}"
    - enabled: true
    - protocol: openid-connect
    - public_client: {{ kc_client.get('public_client', false) }}
    - standard_flow_enabled: true
    - direct_access_grants_enabled: false
    - service_accounts_enabled: {{ kc_client.get('service_accounts_enabled', true) }}
    - redirect_uris: {{ redirect_uris | tojson }}
{%- if kc_client.get('secret') %}
    - secret: {{ kc_client['secret'] | yaml_dquote }}
{%- endif %}
    - keycloak_addr: {{ keycloak_addr }}
    - realm_username: {{ kc_admin['adminUser'] | yaml_dquote }}
    - realm_password: {{ kc_admin['adminPassword'] | yaml_dquote }}
    - verify: {{ kc_conn.get('verify', false) }}
{% endif %}
