include:
  - /formulas/keycloak/install

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
    - spec: {{ pillar['kc-db']['db']['spec'] }}

{% set kcert = pillar['kc-cluster']['cert'] %}
create_keycloak_cert:
  k8s.certmanager_certificate_present:
    - namespace: {{ kcert['namespace'] }}
    - certificate_name: {{ kcert['name'] }}
    - secret_name: {{ kcert['name'] }}-tls
    - common_name: {{ kcert['commonName'] }}
    - email_address: {{ kcert['emailAddress'] }}
    - dns_names: {{ kcert['dns_names'] }}
    - issuer_name: {{ kcert['issuer_name'] }}
    - issuer_kind: {{ kcert['issuer_kind'] }}

create_keycloak_ingress:
  k8s.ingress_present:
    - name: {{ kcluster['ingress']['name'] }}
    - namespace: {{ kcluster['ingress']['namespace'] }}
    - hosts: {{ kcluster['ingress']['hosts'] }}
    - tls:
      - secret_name: {{ kcert['name'] }}-tls
        hosts: {{ kcert['dns_names'] }}
    - ingress_class_name: {{ kcluster['ingress']['class_name'] }}
    - annotations: {{ kcluster['ingress']['annotations'] }}
    - require:
      - k8s: create_keycloak_cert
ensure_keycloak_cluster:
  k8s.keycloak_cluster_present:
    - namespace: {{ kcluster['ingress']['namespace'] }}
    - hostname: {{ kcert['commonName'] }}
    - cluster_name: {{ kcluster['ingress']['namespace'] }}
    - start_optimized: False
    - instances: 2
    - image: quay.io/keycloak/keycloak:{{ kcluster['version'] }}
    - db_vendor: postgres
    - db_host: {{ kdb['db']['name'] }}-rw
    - db_port: 5432
    - db_name: {{ kdb['db']['name'] }}
    - db_user_name_secret_name: {{ kdb['db']['spec']['superuserSecret']['name'] }}
    - db_user_name_secret_key: username
    - db_password_secret_name: {{ kdb['db']['spec']['superuserSecret']['name'] }}
    - db_password_secret_key: password
    - ingress_enabled: False
    - proxy_headers: forwarded
    - tls_secret: {{ kcert['name'] }}-tls
