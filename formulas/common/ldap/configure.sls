include:
  - /formulas/common/ldap/install

# Manage Certificate for TLS using certmanager_certificate_present from k8s.py, with pillar-driven values
ldap_tls_cert:
  k8s.certmanager_certificate_present:
    - name: {{ pillar.get('ldap:cert:name') }}
    - namespace: {{ pillar.get('ldap:cert:namespace') }}
    - secret_name: {{ pillar.get('ldap:cert:secret_name') }}
    - issuer_name: {{ pillar.get('ldap:cert:issuer_name') }}
    - issuer_kind: {{ pillar.get('ldap:cert:issuer_kind') }}
    - common_name: {{ pillar.get('ldap:cert:common_name') }}
    - dns_names: {{ pillar.get('ldap:cert:dns_names') }}
    - ip_addresses: {{ pillar.get('ldap:cert:ip_addresses') }}
    - duration: {{ pillar.get('ldap:cert:duration') }}
    - renew_before: {{ pillar.get('ldap:cert:renew_before') }}

# # Create a PersistentVolumeClaim for LDAP storage using the new state
# ldap_pvc:
#   k8s.pvc_present:
#     - pvc_name: {{ pillar.get('ldap:pv:name', 'ldap-pvc') }}
#     - namespace: {{ pillar.get('ldap:namespace', 'ldap') }}
#     - storage_class: {{ pillar.get('ldap:pv:storage_class', 'local-storage') }}
#     - storage_size: {{ pillar.get('ldap:pv:capacity', '5Gi') }}
#     - access_modes: {{ pillar.get('ldap:pv:access_modes', ['ReadWriteOnce']) }}
#     - selector: {{ pillar.get('ldap:pv:selector', {'matchLabels': {'type': 'local-storage'}}) }}
#     - require:
#       - k8s_helm: install_openldap_ha
