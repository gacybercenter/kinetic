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

# Secret for our own Admin REST API access (kinetic_keycloak.get_admin_token),
# NOT the chart's own bootstrap secret. Sourced from the same
# keycloak.adminUser/adminPassword values driving the Helm release below, so
# it always matches whatever Keycloak was actually bootstrapped with. This is
# distinct from create_dbsuperuser_secret above (that is the Postgres
# database superuser, unrelated to the Keycloak application admin login).
# res-k8s:keycloak:connection:secret_name should point at this secret
# (defaults to "keycloak-admin" if unset).
ensure_keycloak_admin_secret:
  k8s.secret_present:
    - namespace: keycloak
    - secret_name: keycloak-admin
    - data:
        username: {{ pillar['res-k8s']['keycloak']['values']['keycloak']['adminUser'] }}
        password: {{ pillar['res-k8s']['keycloak']['values']['keycloak']['adminPassword'] }}
    - secret_type: Opaque
    - labels:
        app: keycloak
        role: admin-api
    - annotations:
        description: Admin REST API credentials for kinetic_keycloak (matches keycloak.adminUser/adminPassword)
    - require:
      - k8s: ensure_keycloak_namespace

keycloak_install:
  k8s_helm.helm_release_present:
    - release_name: keycloak
    - chart_name: {{ pillar['res-k8s']['keycloak']['chart_name'] }}
    - namespace: keycloak
    - pillar_key: res-k8s:keycloak:values
