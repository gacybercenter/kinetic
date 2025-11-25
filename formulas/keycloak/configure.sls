include:
  - /formulas/keycloak/install

# Ensure the namespace for Keycloak exists
ensure_keycloak_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar.get('kc-db:auth:0:namespace', 'keycloak') }}

# Create a Kubernetes Secret for the database superuser credentials
{% set dbsuperuser = pillar.get('kc-db:dbsuperuser', {}) %}
create_dbsuperuser_secret:
  k8s.secret_present:
    - namespace: {{ pillar.get('kc-db:auth:0:namespace', 'keycloak') }}
    - secret_name: auth-superuser
    - data:
        username: {{ dbsuperuser.get('user') }}
        password: {{ dbsuperuser.get('password') }}
    - secret_type: Opaque
    - labels:
        app: keycloak-db
        role: superuser
    - annotations:
        description: Superuser credentials for Keycloak database
    - require:
      - k8s: ensure_keycloak_namespace