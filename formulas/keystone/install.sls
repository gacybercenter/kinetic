# Secret mounted by the keystone chart at /etc/keystone/ldap/tls.ca
# (subPath: tls.ca) when endpoints.ldap.auth.client.tls.ca is set. The
# chart only *mounts* this secret - it does not create it, so we manage
# it ourselves here, using the same CA value from pillar that also
# populates endpoints.ldap.auth.client.tls.ca in the osh:keystone values.
keystone_ldap_tls_secret:
  k8s.secret_present:
    - namespace: openstack
    - secret_name: keystone-ldap-tls
    - data:
        tls.ca: |
{{ pillar['osh']['keystone']['endpoints']['ldap']['auth']['client']['tls']['ca'] | indent(10, true) }}
