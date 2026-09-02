# The LDAP CA is now mounted directly from the trust-manager Bundle's
# target ConfigMap (synced into the openstack namespace) rather than a
# Secret - see pod.mounts.keystone_api.keystone_api in
# formulas/keystone/files/keystone-wsgi-values.yaml.j2. No local secret
# needs to be managed here anymore.
