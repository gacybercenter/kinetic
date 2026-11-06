# Guacamole pillar

Chart values go in `osh:guacamole:values`. The formula owns everything
else under `osh:guacamole`: namespace, chart pin, CloudNativePG cluster,
and the Gateway HTTPRoute.

The formula forces an external database and turns chart Ingress off.
Do not enable `postgresql` or `ingress` in `values`. Passwords belong in
`db`, not in the chart values. Encrypt them the same way as other
secrets.

CNPG creates `guacamole_db` and the owner only when the Cluster is first
created (`bootstrap.initdb`). The chart's init Job then loads the
Guacamole schema. `bootstrap.initdb.secret.name` must be the app secret
the formula creates (`<cluster>-app` unless `db.app_secret` is set), and
`bootstrap.initdb.owner` / `database` must match `db.user` / `db.name`.
`spec.superuserSecret` must name `<cluster>-superuser`.

The chart NetworkPolicy drops the Gateway unless `values` allow the
ingress namespace. Default login after schema init is `guacadmin` /
`guacadmin`. Change it. Do not put that password here.

```yaml
osh:
  guacamole:
    namespace: guacamole
    release_name: guacamole          # also the Service name
    chart_name: helmforge/guacamole
    chart_version: "1.7.1"           # appVersion 1.6.0
    service_port: 80
    # web app only. Chart pins the upstream image by digest; the formula
    # clears image.digest. guacd stays the chart default.
    image:
      repository: registry.gitlab.com/gacybercenter/open/kinetic/containers/kinetic-guacamole
      tag: latest
      pull_policy: Always
    # image_pull_secret: gitlab-registry   # required if the project is private
    gateway_name: traefik-external
    gateway_namespace: ingress
    gateway_section: websecure-ext
    ingress:
      hosts:
        - guac.rsc.gacyberrange.org
    # optional; client id defaults to guacamole in realm rsc
    keycloak:
      realm: rsc
      client_id: guacamole
      client_name: Guacamole
    db:
      cluster_name: guacamole-db     # Service is guacamole-db-rw
      name: guacamole_db
      user: guacamole_user
      password: "<encrypted>"
      superuser:
        user: postgres
        password: "<encrypted>"
      spec:
        instances: 1
        imageName: ghcr.io/cloudnative-pg/postgresql:17
        bootstrap:
          initdb:
            database: guacamole_db
            owner: guacamole_user
            secret:
              name: guacamole-db-app
        superuserSecret:
          name: guacamole-db-superuser
        storage:
          size: 10Gi
          storageClass: rook-ceph-block
    values:
      # required: Gateway lives in another namespace
      networkPolicy:
        ingressFrom:
          - namespaceSelector:
              matchLabels:
                kubernetes.io/metadata.name: ingress
      # OpenID is not loaded unless named here. Do not pass this through
      # helm --set: the comma is parsed as another --set value.
      guacamole:
        extraEnv:
          - name: EXTENSION_PRIORITY
            value: "*, openid"
          - name: OPENID_LOGOUT_ENDPOINT
            value: https://keycloak.rsc.gacyberrange.org/realms/rsc/protocol/openid-connect/logout
          - name: OPENID_POST_LOGOUT_REDIRECT_URI
            value: https://rsc.gacyberrange.org/
      oidc:
        enabled: true
        authorizationEndpoint: https://keycloak.rsc.gacyberrange.org/realms/rsc/protocol/openid-connect/auth
        jwksEndpoint: https://keycloak.rsc.gacyberrange.org/realms/rsc/protocol/openid-connect/certs
        issuer: https://keycloak.rsc.gacyberrange.org/realms/rsc
        clientId: guacamole
        redirectUri: https://guac.rsc.gacyberrange.org/
        scope: "openid email profile"
        usernameClaim: preferred_username
        groupsClaim: groups
      proxy:
        enabled: true
        protocolHeader: X-Forwarded-Proto
        ipHeader: X-Forwarded-For
```

Apply:

```bash
salt-run state.orchestrate orch.k8s-guacamole pillar='{"k8s": "<minion>"}'
```

The formula registers client `guacamole` in realm `rsc` (public, PKCE
S256, implicit flow on). Guacamole's OpenID extension uses
`response_type=id_token`. Leaving implicit flow off produces
"Implicit flow is disabled for the client." Redirects, web origins, and post-logout redirects
(`post.logout.redirect.uris`, `https://<host>/`) come from `ingress.hosts`
(`https://<host>/*` and `https://<host>`). Override with
`osh:guacamole:keycloak`. Default scopes are `profile`, `email`, and
`groups`. The `groups` scope must already exist; the LDAP group mapper
puts the bare `cn` in that claim. Chart `values.oidc.clientId` must be
this client id. Redirect URI in the chart is `https://<host>/` when
`guacamole.contextPath` stays `ROOT`. The chart has no client-secret
field, so do not set `public_client: false`.
