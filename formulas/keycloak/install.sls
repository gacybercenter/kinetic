include:
  - /formulas/common/helm
  - /formulas/common/k8s-cnpg

# Ensure the namespace for Keycloak exists
{% set kcluster = pillar['kc-cluster'] %}
{% set kdb = pillar['kc-db'] %}

ensure_keycloak_namespace:
  k8s.namespace_present:
    - namespace: {{ kdb['namespace'] }}

# Create a Kubernetes Secret for the database superuser credentials
create_dbsuperuser_secret:
  k8s.secret_present:
    - namespace: {{ pillar['kc-db']['namespace'] }}
    - secret_name: {{ kdb['db']['name'] }}-superuser
    - data:
        username: {{ pillar['kc-db']['dbsuperuser']['user'] }}
        password: {{ pillar['kc-db']['dbsuperuser']['password'] }}
    - secret_type: Opaque
    - labels:
        app: keycloak-db
        role: superuser
    - annotations:
        description: Superuser credentials for Keycloak database
    - require:
      - k8s: ensure_keycloak_namespace

create_auth_pg_cluster:
  k8s.cnpg_cluster_present:
    - cluster_name: {{ pillar['kc-db']['db']['name'] }}
    - namespace: {{ pillar['kc-db']['namespace'] }}
    - spec: {{ pillar['kc-db']['db']['spec'] | tojson }}

{% set cm = pillar['res-k8s']['logger-kc-cm'] %}
ensure_ldap_fluentbit_configmap:
  k8s.configmap_present:
    - name: {{ cm['name'] }}
    - configmap_name: {{ cm['name'] }}
    - namespace: keycloak
    - data: {{ cm['data'] | yaml }}

{# Implements: 800-171 3.1.9 — custom login theme; notice text from pillar only. #}
{% set rsc_realm = pillar.get('ldap', {}).get('realms', {}).get('rsc', {}) %}
{% set login_notice = rsc_realm.get('login_notice', pillar.get('res-k8s', {}).get('keycloak', {}).get('login_notice', '')) %}
{% set theme_parent = pillar.get('res-k8s', {}).get('keycloak', {}).get('login_theme_parent', 'keycloak.v2') %}
{% set login_ftl = salt['cp.get_file_str']('salt://formulas/keycloak/themes/gcr-login/login/login.ftl') %}
{% set notice_css = salt['cp.get_file_str']('salt://formulas/keycloak/themes/gcr-login/login/resources/css/notice.css') %}
{% set notice_prop = login_notice.replace('\\', '\\\\').replace('\n', '\\n') %}
{% set theme_data = {
  'theme.properties': 'parent=' ~ theme_parent ~ '\nimport=common/keycloak\nstyles=css/login.css css/notice.css\n',
  'login.ftl': login_ftl,
  'messages_en.properties': 'loginNotice=' ~ notice_prop ~ '\n',
  'notice.css': notice_css,
} %}

keycloak_gcr_login_theme:
  k8s.configmap_present:
    - name: keycloak-gcr-login-theme
    - configmap_name: keycloak-gcr-login-theme
    - namespace: keycloak
    - data: {{ theme_data | tojson }}
    - labels:
        app: keycloak
        theme: gcr-login
    - require:
      - k8s: ensure_keycloak_namespace

keycloak_theme_values_file:
  file.managed:
    - name: /tmp/keycloak-gcr-login-theme-values.yaml
    - source: salt://formulas/keycloak/files/theme-values.yaml.j2
    - template: jinja
    - mode: '0600'
    - user: root
    - group: root
    - require:
      - k8s: keycloak_gcr_login_theme

keycloak_install:
  k8s_helm.helm_release_present:
    - release_name: keycloak
    - chart_name: {{ pillar['res-k8s']['keycloak']['chart_name'] }}
    - namespace: keycloak
    - pillar_key: res-k8s:keycloak:values
    - values_files:
      - /tmp/keycloak-gcr-login-theme-values.yaml
    - require:
      - file: keycloak_theme_values_file
