include:
  - /formulas/keycloak/install

# Ensure the namespace for Keycloak exists
ensure_keycloak_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar['kc-db']['namespace'] }}

# Create a Kubernetes Secret for the database superuser credentials
{% set dbsuperuser = pillar.get('kc-db:dbsuperuser', {}) %}
create_dbsuperuser_secret:
  k8s.secret_present:
    - namespace: {{ pillar['kc-db']['namespace'] }}
    - secret_name: auth-superuser
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