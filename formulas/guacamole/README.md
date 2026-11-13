# Guacamole formula

Chart values are `osh:guacamole:values`. Namespace, CloudNativePG cluster,
HTTPRoute, Keycloak client, and JDBC grants are the rest of
`osh:guacamole`. Pillar shape is in `PILLAR-EXAMPLE.md`.

```bash
salt-run state.orchestrate orch.k8s-guacamole pillar='{"k8s": "<minion>"}'
```

## api_user password

`api_user` is a JDBC login, not an OpenID user. Set the encrypted plaintext
password only. Do not compute a hash.

```yaml
osh:
  guacamole:
    api_user:
      name: api-user
      password: "<encrypted plaintext>"
      permissions:
        - CREATE_CONNECTION
```

The formula copies `password` into Secret `guacamole-api-user` (override
with `api_user.secret_name`) in the guacamole namespace. Keys are `username`
and `password`. Callers in that namespace should read the Secret, not pillar.

`guacamole-admin-grant` then computes the Guacamole hash. Guacamole stores
SHA-256 of the UTF-8 string `password + UPPERCASE_HEX(salt)`, not the raw
salt bytes. The Job reads `password_salt` from `guacamole_user` if the user
already exists, otherwise it draws 32 bytes from `/dev/urandom`. It writes
the hash and salt with `decode(..., 'hex')` and skips the update when the
stored hash already matches. A later password change recreates the Job.

Omit `password` to skip the user and the Secret. `password_hash` and
`password_salt` are only used when `password` is omitted. That path is for
a user that already has a hash. Prefer `password`.

`CREATE_CONNECTION` is the only permission this user gets. Guacamole then
lets that user administer connections it creates. This is not
`ADMINISTER`. Removing a permission from pillar does not revoke it.
