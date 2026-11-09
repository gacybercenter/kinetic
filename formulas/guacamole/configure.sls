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
{% set admin_group = guac.get('admin_group', 'admins') %}
{% set sql_admin_group = admin_group | replace("'", "''") %}
{# REST user. Hash and salt are Guacamole JDBC SHA-256(password || salt),
   hex, not the plaintext password. Missing hash skips the user. #}
{% set api = guac.get('api_user', {}) %}
{% set api_name = api.get('name', 'api-user') %}
{% set sql_api_name = api_name | replace("'", "''") %}
{% set api_hash = (api.get('password_hash', '') | string) | replace(' ', '') | replace('\n', '') | lower %}
{% set api_salt = (api.get('password_salt', '') | string) | replace(' ', '') | replace('\n', '') | lower %}
{% set api_perms = api.get('permissions', ['CREATE_CONNECTION']) %}
{# Chart values pin docker.io/guacamole/guacamole by digest. A tag change
   is ignored until image.digest is null. This image is the web app only;
   guacd stays the chart default unless values override it. #}
{% set image = guac.get('image', {}) %}
{% set image_repo = image.get('repository', 'registry.gitlab.com/gacybercenter/open/kinetic/containers/kinetic-guacamole') %}
{% set image_tag = image.get('tag', 'latest') %}
{% set image_pull_policy = image.get('pull_policy', 'Always' if image_tag == 'latest' else 'IfNotPresent') %}

{% set hostnames = [] %}
{% for h in guac.get('ingress', {}).get('hosts', []) %}
{% if h is mapping %}
{% do hostnames.append(h['host']) %}
{% else %}
{% do hostnames.append(h) %}
{% endif %}
{% endfor %}

{# Public OIDC client. The helmforge chart has no client-secret field, so this
   stays public (PKCE S256). Redirects follow ingress.hosts. The chart does not
   infer redirectUri when Ingress is off, so values.oidc.redirectUri must be
   https://<first host>/ and values.oidc.clientId must be this client_id. #}
{% set kc = pillar.get('res-k8s', {}).get('keycloak', {}) %}
{% set kc_conn = kc.get('connection', {}) %}
{% set kc_oidc = guac.get('keycloak', {}) %}
{% set kc_realm = kc_oidc.get('realm', 'rsc') %}
{% set kc_client = kc_oidc.get('client_id', 'guacamole') %}
{% set guac_redirects = kc_oidc.get('redirect_uris', []) %}
{% if not kc_oidc.get('redirect_uris') %}
{% for h in hostnames %}
{% do guac_redirects.append('https://' ~ h ~ '/*') %}
{% endfor %}
{% endif %}
{% set guac_origins = kc_oidc.get('web_origins', []) %}
{% if not kc_oidc.get('web_origins') %}
{% for h in hostnames %}
{% do guac_origins.append('https://' ~ h) %}
{% endfor %}
{% endif %}
{# OPENID_POST_LOGOUT_REDIRECT_URI must be listed here. Valid Redirect URIs
   do not cover RP-initiated logout. Keycloak wants them ##-separated. #}
{% set logout_uris = kc_oidc.get('post_logout_redirect_uris', []) %}
{% if not kc_oidc.get('post_logout_redirect_uris') %}
{% for h in hostnames %}
{% do logout_uris.append('https://' ~ h ~ '/') %}
{% do logout_uris.append('https://' ~ h ~ '/*') %}
{% endfor %}
{% endif %}

guacamole_keycloak_client:
  keycloak.client_present:
    - name: {{ kc_client }}
    - realm: {{ kc_realm }}
    - client_id: {{ kc_client }}
    - client_name: {{ kc_oidc.get('client_name', 'Guacamole') | yaml_dquote }}
    - description: "Apache Guacamole OIDC client"
    - enabled: true
    - protocol: openid-connect
    - public_client: {{ kc_oidc.get('public_client', true) }}
    - standard_flow_enabled: true
    - direct_access_grants_enabled: false
    - service_accounts_enabled: false
    {# guacamole-auth-openid sends response_type=id_token. Standard flow is
       authorization code, which Keycloak rejects with "Implicit flow is
       disabled for the client." #}
    - spec:
        implicitFlowEnabled: {{ kc_oidc.get('implicit_flow_enabled', true) }}
    - redirect_uris: {{ guac_redirects | tojson }}
    - web_origins: {{ guac_origins | tojson }}
{%- if logout_uris %}
    - attributes:
        post.logout.redirect.uris: {{ logout_uris | join('##') | yaml_dquote }}
{%- endif %}
    - keycloak_addr: {{ kc_conn.get('keycloak_addr', 'k8s://keycloak/keycloak-service:8443') }}
    - namespace: {{ kc_conn.get('namespace', 'keycloak') }}
    - secret_name: {{ kc_conn.get('secret_name', 'keycloak-admin') }}
    - verify: {{ kc_conn.get('verify', false) }}

{% for scope_name in kc_oidc.get('default_client_scopes', ['profile', 'email', 'groups']) %}
guacamole_keycloak_client_default_scope_{{ scope_name }}:
  keycloak.client_default_scope_present:
    - name: {{ kc_client }}
    - realm: {{ kc_realm }}
    - scope_name: {{ scope_name }}
    - client_id: {{ kc_client }}
    - keycloak_addr: {{ kc_conn.get('keycloak_addr', 'k8s://keycloak/keycloak-service:8443') }}
    - namespace: {{ kc_conn.get('namespace', 'keycloak') }}
    - secret_name: {{ kc_conn.get('secret_name', 'keycloak-admin') }}
    - verify: {{ kc_conn.get('verify', false) }}
    - require:
      - keycloak: guacamole_keycloak_client
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
      - image.repository={{ image_repo }}
      - image.tag={{ image_tag }}
      - image.digest=null
      - image.pullPolicy={{ image_pull_policy }}
{%- if guac.get('image_pull_secret') %}
      - imagePullSecrets[0].name={{ guac['image_pull_secret'] }}
{%- endif %}
    - require:
      - k8s_helm: ensure_helmforge_repo
      - k8s: ensure_guacamole_pg_cluster
{%- if hostnames %}
      - k8s: guacamole_httproute
{%- endif %}

{# OpenID only attaches a user to a Guacamole group of the same name. It does
   not grant rights. The claim must be the bare LDAP cn (admins, not
   /admins). That group may create connections and groups. READ, UPDATE, and
   DELETE are object permissions, not system permissions, so they are granted
   on every connection and connection group. ADMINISTER is revoked.
   api_user is a JDBC login for the REST API. CREATE_CONNECTION only. Removing
   an api_user permission from pillar does not revoke it. #}
{% if admin_group or api_hash %}
guacamole_admin_sql:
  k8s.configmap_present:
    - name: guacamole-admin-sql
    - configmap_name: guacamole-admin-sql
    - namespace: {{ ns }}
    - data:
        grant.sql: |
{%- if admin_group %}
          INSERT INTO guacamole_entity (name, type)
          VALUES ('{{ sql_admin_group }}', 'USER_GROUP')
          ON CONFLICT (type, name) DO NOTHING;
          INSERT INTO guacamole_user_group (entity_id, disabled)
          SELECT entity_id, FALSE FROM guacamole_entity
          WHERE name = '{{ sql_admin_group }}' AND type = 'USER_GROUP'
            AND NOT EXISTS (
              SELECT 1 FROM guacamole_user_group g
              WHERE g.entity_id = guacamole_entity.entity_id
            );
          DELETE FROM guacamole_system_permission
          WHERE entity_id = (
            SELECT entity_id FROM guacamole_entity
            WHERE name = '{{ sql_admin_group }}' AND type = 'USER_GROUP'
          )
          AND permission NOT IN (
            'CREATE_CONNECTION'::guacamole_system_permission_type,
            'CREATE_CONNECTION_GROUP'::guacamole_system_permission_type
          );
          INSERT INTO guacamole_system_permission (entity_id, permission)
          SELECT entity_id, perm::guacamole_system_permission_type
          FROM guacamole_entity,
               (VALUES
                 ('CREATE_CONNECTION'),
                 ('CREATE_CONNECTION_GROUP')
               ) AS perms(perm)
          WHERE name = '{{ sql_admin_group }}' AND type = 'USER_GROUP'
          ON CONFLICT (entity_id, permission) DO NOTHING;
          INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
          SELECT e.entity_id, c.connection_id, p.perm::guacamole_object_permission_type
          FROM guacamole_entity e
          CROSS JOIN guacamole_connection c
          CROSS JOIN (VALUES ('READ'), ('UPDATE'), ('DELETE')) AS p(perm)
          WHERE e.name = '{{ sql_admin_group }}' AND e.type = 'USER_GROUP'
          ON CONFLICT (entity_id, connection_id, permission) DO NOTHING;
          INSERT INTO guacamole_connection_group_permission (entity_id, connection_group_id, permission)
          SELECT e.entity_id, g.connection_group_id, p.perm::guacamole_object_permission_type
          FROM guacamole_entity e
          CROSS JOIN guacamole_connection_group g
          CROSS JOIN (VALUES ('READ'), ('UPDATE'), ('DELETE')) AS p(perm)
          WHERE e.name = '{{ sql_admin_group }}' AND e.type = 'USER_GROUP'
          ON CONFLICT (entity_id, connection_group_id, permission) DO NOTHING;
          DELETE FROM guacamole_connection_permission
          WHERE permission = 'ADMINISTER'
            AND entity_id = (
              SELECT entity_id FROM guacamole_entity
              WHERE name = '{{ sql_admin_group }}' AND type = 'USER_GROUP'
            );
          DELETE FROM guacamole_connection_group_permission
          WHERE permission = 'ADMINISTER'
            AND entity_id = (
              SELECT entity_id FROM guacamole_entity
              WHERE name = '{{ sql_admin_group }}' AND type = 'USER_GROUP'
            );
          CREATE OR REPLACE FUNCTION kinetic_admins_connection_grant()
          RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN
            INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
            SELECT entity_id, NEW.connection_id, perm::guacamole_object_permission_type
            FROM guacamole_entity,
                 (VALUES ('READ'), ('UPDATE'), ('DELETE')) AS perms(perm)
            WHERE name = '{{ sql_admin_group }}' AND type = 'USER_GROUP'
            ON CONFLICT (entity_id, connection_id, permission) DO NOTHING;
            RETURN NEW;
          END;
          $$;
          CREATE OR REPLACE FUNCTION kinetic_admins_connection_group_grant()
          RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN
            INSERT INTO guacamole_connection_group_permission (entity_id, connection_group_id, permission)
            SELECT entity_id, NEW.connection_group_id, perm::guacamole_object_permission_type
            FROM guacamole_entity,
                 (VALUES ('READ'), ('UPDATE'), ('DELETE')) AS perms(perm)
            WHERE name = '{{ sql_admin_group }}' AND type = 'USER_GROUP'
            ON CONFLICT (entity_id, connection_group_id, permission) DO NOTHING;
            RETURN NEW;
          END;
          $$;
          DROP TRIGGER IF EXISTS kinetic_admins_connection_grant ON guacamole_connection;
          CREATE TRIGGER kinetic_admins_connection_grant
            AFTER INSERT ON guacamole_connection
            FOR EACH ROW EXECUTE FUNCTION kinetic_admins_connection_grant();
          DROP TRIGGER IF EXISTS kinetic_admins_connection_group_grant ON guacamole_connection_group;
          CREATE TRIGGER kinetic_admins_connection_group_grant
            AFTER INSERT ON guacamole_connection_group
            FOR EACH ROW EXECUTE FUNCTION kinetic_admins_connection_group_grant();
{%- endif %}
{%- if api_hash and api_salt %}
          INSERT INTO guacamole_entity (name, type)
          VALUES ('{{ sql_api_name }}', 'USER')
          ON CONFLICT (type, name) DO NOTHING;
          INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date)
          SELECT entity_id,
                 decode('{{ api_hash }}', 'hex'),
                 decode('{{ api_salt }}', 'hex'),
                 CURRENT_TIMESTAMP
          FROM guacamole_entity
          WHERE name = '{{ sql_api_name }}' AND type = 'USER'
          ON CONFLICT (entity_id) DO UPDATE
            SET password_hash = EXCLUDED.password_hash,
                password_salt = EXCLUDED.password_salt,
                password_date = CURRENT_TIMESTAMP;
          INSERT INTO guacamole_system_permission (entity_id, permission)
          SELECT entity_id, perm::guacamole_system_permission_type
          FROM guacamole_entity,
               (VALUES
{%- for perm in api_perms %}
                 ('{{ perm | replace("'", "''") }}'){{ ',' if not loop.last else '' }}
{%- endfor %}
               ) AS perms(perm)
          WHERE name = '{{ sql_api_name }}' AND type = 'USER'
          ON CONFLICT (entity_id, permission) DO NOTHING;
{%- endif %}
          UPDATE guacamole_user
          SET disabled = TRUE
          WHERE entity_id = (
            SELECT entity_id FROM guacamole_entity
            WHERE name = 'guacadmin' AND type = 'USER'
          )
          AND disabled = FALSE;
    - require:
      - k8s: ensure_guacamole_namespace

guacamole_admin_grant:
  k8s.job_present:
    - name: guacamole-admin-grant
    - namespace: {{ ns }}
    - image: docker.io/library/postgres:17
    - restart_policy: Never
    - backoff_limit: 6
    - ttl_seconds_after_finished: 600
    {# ConfigMap changes do not change the Job spec. This annotation does,
       so a new hash recreates the Job and reruns the SQL. #}
    - annotations:
        kinetic.rsc.gacyberrange.org/grant: "{{ sql_admin_group }}:{{ sql_api_name }}:{{ api_perms | join(',') }}:{{ api_hash[:16] }}:{{ api_salt[:16] }}:admins-locked"
    - command:
      - sh
      - -c
      - until psql -v ON_ERROR_STOP=1 -f /sql/grant.sql; do sleep 5; done
    - env:
      - name: PGHOST
        value: {{ cluster }}-rw
      - name: PGPORT
        value: "5432"
      - name: PGDATABASE
        value: {{ db_name }}
      - name: PGUSER
        value: {{ db_user }}
      - name: PGPASSWORD
        valueFrom:
          secretKeyRef:
            name: {{ app_secret }}
            key: password
    - volumes:
      - name: sql
        configMap:
          name: guacamole-admin-sql
    - volume_mounts:
      - name: sql
        mountPath: /sql
    - require:
      - k8s: guacamole_admin_sql
      - k8s_helm: install_guacamole
{% endif %}
