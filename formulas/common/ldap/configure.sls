include:
  - /formulas/common/ldap/install

# Manage Certificate for TLS using certmanager_certificate_present from k8s.py, with pillar-driven values
ldap_tls_cert:
  k8s.certmanager_certificate_present:
    - certificate_name: {{ pillar.get('ldap:cert:name') }}
    - namespace: {{ pillar['ldap']['cert']['namespace'] }}
    - secret_name: {{ pillar.get('ldap:cert:secret_name') }}
    - issuer_name: {{ pillar.get('ldap:cert:issuer_name') }}
    - issuer_kind: {{ pillar.get('ldap:cert:issuer_kind') }}
    - common_name: {{ pillar.get('ldap:cert:common_name') }}
    - dns_names: {{ pillar.get('ldap:cert:dns_names') }}
    - ip_addresses: {{ pillar.get('ldap:cert:ip_addresses') }}
    - duration: {{ pillar.get('ldap:cert:duration') }}
    - renew_before: {{ pillar.get('ldap:cert:renew_before') }}

# Create an Ingress for LDAP to route external traffic to the service
ldap_ingress:
  k8s.ingress_present:
    - name: {{ pillar.get('ldap:ingress:name') }}
    - namespace: {{ pillar.get('ldap:namespace') }}
    - hosts: {{ pillar.get('ldap:ingress:hosts') }}
    - tls:
      - secret_name: {{ pillar.get('ldap:cert:secret_name') }}
        hosts: {{ pillar.get('ldap:cert:dns_names') }}
    - ingress_class_name: {{ pillar.get('ldap:ingress:class_name') }}
    - annotations: {{ pillar.get('ldap:ingress:annotations') }}
    - require:
      - k8s: ldap_tls_cert

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
