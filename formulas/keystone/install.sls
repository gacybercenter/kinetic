# Secret mounted by the keystone chart at /etc/keystone/ldap/tls.ca
# (subPath: tls.ca) when endpoints.ldap.auth.client.tls.ca is set. The
# chart only *mounts* this secret - it does not create it, so we manage
# it ourselves here.
#
# The CA is read directly from a trust-manager Bundle's target ConfigMap
# (synced into the openstack namespace) rather than from pillar. The
# Bundle/ConfigMap name comes from pillar res-k8s:rsc-cert-ca.
{% set rsc_cert_ca_bundle = pillar['res-k8s']['rsc-cert-ca']['name'] %}
keystone_ldap_tls_secret:
  k8s.secret_present:
    - namespace: openstack
    - secret_name: keystone-ldap-tls
    - data:
        tls.ca: |
{{ salt['kinetic_k8s.get_configmap_value']('openstack', rsc_cert_ca_bundle, 'ca.crt', '') | indent(10, true) }}
