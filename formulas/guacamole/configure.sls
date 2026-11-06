include:
  - /formulas/guacamole/install

{# ---------------------------------------------------------------------------
   osh:guacamole          this formula (namespace, chart pin, CNPG, route)
   osh:guacamole:values   Helm values only. Do not put the cluster spec or
                          hostnames here.

   The chart's bundled Postgres is turned off below. CNPG owns the database.
   TLS terminates on the Gateway. Chart Ingress stays off; this HTTPRoute is
   the public path.

   The app secret is both the CNPG bootstrap.initdb.secret and the chart's
   database.external.existingSecret. Keys must be username and password.
   bootstrap.initdb.owner must be that username, and database must be
   osh:guacamole:db:name. CNPG only applies bootstrap at cluster create.
   The chart init Job then loads the Guacamole schema.

   Chart networkPolicy is on by default and drops the Gateway. The values
   pillar has to allow the ingress namespace, or the route will 404/timeout:

     networkPolicy:
       ingressFrom:
         - namespaceSelector:
             matchLabels:
               kubernetes.io/metadata.name: ingress
   --------------------------------------------------------------------------- #}
{% set guac = pillar['osh']['guacamole'] %}
{% set ns = guac.get('namespace', 'guacamole') %}
{% set release = guac.get('release_name', 'guacamole') %}
{% set chart = guac.get('chart_name', 'helmforge/guacamole') %}
{% set db = guac['db'] %}
{% set cluster = db.get('cluster_name', 'guacamole-db') %}
{% set app_secret = db.get('app_secret', cluster ~ '-app') %}
{% set super_secret = db.get('superuser_secret', cluster ~ '-superuser') %}
{% set db_name = db.get('name', 'guacamole_db') %}
{% set db_user = db['user'] %}
{% set service_port = guac.get('service_port', 80) %}

{% set hostnames = [] %}
{% for h in guac.get('ingress', {}).get('hosts', []) %}
{% if h is mapping %}
{% do hostnames.append(h['host']) %}
{% else %}
{% do hostnames.append(h) %}
{% endif %}
{% endfor %}

ensure_guacamole_app_secret:
  k8s.secret_present:
    - namespace: {{ ns }}
    - secret_name: {{ app_secret }}
    - data:
        username: {{ db_user | yaml_dquote }}
        password: {{ db['password'] | yaml_dquote }}
    - secret_type: Opaque
    - labels:
        app: guacamole
        cnpg.io/reload: "true"
    - require:
      - k8s: ensure_guacamole_namespace

ensure_guacamole_superuser_secret:
  k8s.secret_present:
    - namespace: {{ ns }}
    - secret_name: {{ super_secret }}
    - data:
        username: {{ db['superuser']['user'] | yaml_dquote }}
        password: {{ db['superuser']['password'] | yaml_dquote }}
    - secret_type: Opaque
    - labels:
        app: guacamole
        cnpg.io/reload: "true"
        role: superuser
    - require:
      - k8s: ensure_guacamole_namespace

ensure_guacamole_pg_cluster:
  k8s.cnpg_cluster_present:
    - cluster_name: {{ cluster }}
    - namespace: {{ ns }}
    - spec: {{ db['spec'] | tojson }}
    - require:
      - k8s: ensure_guacamole_app_secret
      - k8s: ensure_guacamole_superuser_secret
      - sls: /formulas/common/k8s-cnpg

{% if hostnames %}
# TLS terminates on the Gateway. The chart Service is <release> (fullname
# is pinned below) and listens on service.port, which defaults to 80 and
# targets Tomcat's http listener.
guacamole_httproute:
  k8s.httproute_present:
    - name: {{ release }}-route
    - namespace: {{ ns }}
    - parent_refs:
        - name: {{ guac.get('gateway_name', 'traefik-external') }}
          namespace: {{ guac.get('gateway_namespace', 'ingress') }}
          sectionName: {{ guac.get('gateway_section', 'websecure-ext') }}
    - hostnames: {{ hostnames | tojson }}
    - rules:
        - matches:
            - path:
                type: PathPrefix
                value: "/"
          backendRefs:
            - name: {{ release }}
              port: {{ service_port }}
    - require:
      - k8s: ensure_guacamole_namespace
{% endif %}

install_guacamole:
  k8s_helm.helm_release_present:
    - release_name: {{ release }}
    - chart_name: {{ chart }}
    - namespace: {{ ns }}
    - version: {{ guac.get('chart_version', '1.7.1') | yaml_dquote }}
    - wait_timeout: {{ guac.get('wait_timeout', 600) }}
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh:guacamole:values
    {# External CNPG, not the bundled subchart. Chart Ingress is unused. #}
    - set_values:
      - fullnameOverride={{ release }}
      - postgresql.enabled=false
      - mysql.enabled=false
      - ingress.enabled=false
      - database.type=postgresql
      - database.external.host={{ cluster }}-rw
      - database.external.port=5432
      - database.external.name={{ db_name }}
      - database.external.username={{ db_user }}
      - database.external.existingSecret={{ app_secret }}
      - database.external.existingSecretPasswordKey=password
      - service.port={{ service_port }}
    - require:
      - k8s_helm: ensure_helmforge_repo
      - k8s: ensure_guacamole_pg_cluster
{%- if hostnames %}
      - k8s: guacamole_httproute
{%- endif %}
