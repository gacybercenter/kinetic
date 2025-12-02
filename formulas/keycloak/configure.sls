include:
  - /formulas/keycloak/install

# Ensure the namespace for Keycloak exists
ensure_keycloak_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar['kc-db']['namespace'] }}

# Create a Kubernetes Secret for the database superuser credentials
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

create_auth_pg_cluster:
  k8s.cnpg_cluster_present:
    - cluster_name: {{ pillar['kc-db']['db']['name'] }}
    - namespace: {{ pillar['kc-db']['namespace'] }}
    - spec: {{ pillar['kc-db']['db']['spec'] }}

{% set kcert = pillar['kc-cluster']['cert'] %}
create_keycloak_cert:
  k8s.certificate_present:
    - namespace: {{ kcert['namespace'] }}
    - name: {{ kcert['name'] }}
    - certificate_name: {{ kcert['name'] }} 
    - common_name: {{ kcert['commonName'] }}
    - email_address: {{ kcert['emailAddress'] }}
    - issuer_ref: 
      - name: {{ kcert['issuerRef']['name'] }}
      - kind: {{ kcert['issuerRef']['kind'] }}
create_keycloak_ingress:
  k8s.ingress_present:
    - namespace: {{ kcert['namespace'] }}
    - ingress_name: {{ kcert['name'] }}-ingress
    - spec:
        ingressClassName: nginx
        rules:
          - host: {{ kcert['commonName'] }}
            http:
              paths:
                - path: /
                  pathType: Prefix
                  backend:
                    service:
                      name: {{ kc-cluster['svc_name'] }}
                      port:
                        number: {{ kc-cluster['svc_port'] }}
        tls:
          - hosts:
              - {{ kcert['commonName'] }}
            secretName: {{ kcert['name'] }}-tls
    - annotations:
        nginx.ingress.kubernetes.io/rewrite-target: /