# Manage Certificate for TLS using certmanager_certificate_present from k8s.py, with pillar-driven values
ldap_tls_cert:
  k8s.certmanager_certificate_present:
    - name: {{ pillar.get('ldap:cert:name', 'ldap-tls-cert') }}
    - namespace: {{ pillar.get('ldap:cert:namespace', 'openldap-ha') }}
    - secret_name: {{ pillar.get('ldap:cert:secret_name', 'tls-cert') }}
    - issuer_name: {{ pillar.get('ldap:cert:issuer_name', 'selfsigned-issuer') }}
    - issuer_kind: {{ pillar.get('ldap:cert:issuer_kind', 'ClusterIssuer') }}
    - common_name: {{ pillar.get('ldap:cert:common_name', 'ldap.dev-gacyberrange.org') }}
    - dns_names: {{ pillar.get('ldap:cert:dns_names', [
        'ldap.dev-gacyberrange.org',
        'my-openldap-ha-openldap.openldap-ha.svc',
        'my-openldap-ha-openldap.openldap-ha.svc.cluster.local',
        'localhost',
        '127.0.0.1'
      ]) }}
    - ip_addresses: {{ pillar.get('ldap:cert:ip_addresses', ['127.0.0.1']) }}
    - duration: {{ pillar.get('ldap:cert:duration', '2160h') }}
    - renew_before: {{ pillar.get('ldap:cert:renew_before', '360h') }}

# Create a PersistentVolumeClaim for LDAP storage using the new state
ldap_pvc:
  k8s.pvc_present:
    - pvc_name: {{ pillar.get('ldap:pv:name', 'ldap-pvc') }}
    - namespace: {{ pillar.get('ldap:namespace', 'ldap') }}
    - storage_class: {{ pillar.get('ldap:pv:storage_class', 'local-storage') }}
    - storage_size: {{ pillar.get('ldap:pv:capacity', '5Gi') }}
    - access_modes: {{ pillar.get('ldap:pv:access_modes', ['ReadWriteOnce']) }}
    - selector: {{ pillar.get('ldap:pv:selector', {'matchLabels': {'type': 'local-storage'}}) }}
    - require:
      - k8s_helm: install_openldap_ha
