include:
  - /formulas/common/ldap/install

# Manage Certificate for TLS using certmanager_certificate_present from k8s.py, with pillar-driven values
ldap_tls_cert:
  k8s.certmanager_certificate_present:
    - name: {{ pillar['ldap']['cert']['name'] }}
    - certificate_name: {{ pillar['ldap']['cert']['name'] }}
    - namespace: {{ pillar['ldap']['cert']['namespace'] }}
    - secret_name: {{ pillar['ldap']['cert']['secret_name'] }}
    - issuer_name: {{ pillar['ldap']['cert']['issuer_name'] }}
    - issuer_kind: {{ pillar['ldap']['cert']['issuer_kind'] }}
    - common_name: {{ pillar['ldap']['cert']['common_name'] }}
    - dns_names: {{ pillar['ldap']['cert']['dns_names'] }}
    - ip_addresses: {{ pillar['ldap']['cert']['ip_addresses'] }}
    - duration: {{ pillar['ldap']['cert']['duration'] }}
    - renew_before: {{ pillar['ldap']['cert']['renew_before'] }}

# Create an Ingress for LDAP to route external traffic to the service
ldap_ingress:
  k8s.ingress_present:
    - name: {{ pillar['ldap']['ingress']['name'] }}
    - namespace: {{ pillar['ldap']['namespace'] }}
    - hosts: {{ pillar['ldap']['ingress']['hosts'] }}
    - tls:
      - secret_name: {{ pillar['ldap']['cert']['secret_name'] }}
        hosts: {{ pillar['ldap']['cert']['dns_names'] }}
    - ingress_class_name: {{ pillar['ldap']['ingress']['class_name'] }}
    - annotations: {{ pillar['ldap']['ingress']['annotations'] }}
    - require:
      - k8s: ldap_tls_cert

# # Create a PersistentVolumeClaim for LDAP storage using the new state
# ldap_pvc:
#   k8s.pvc_present:
#     - pvc_name: {{ pillar['ldap']['pv'].get('name', 'ldap-pvc') }}
#     - namespace: {{ pillar['ldap'].get('namespace', 'ldap') }}
#     - storage_class: {{ pillar['ldap']['pv'].get('storage_class', 'local-storage') }}
#     - storage_size: {{ pillar['ldap']['pv'].get('capacity', '5Gi') }}
#     - access_modes: {{ pillar['ldap']['pv'].get('access_modes', ['ReadWriteOnce']) }}
#     - selector: {{ pillar['ldap']['pv'].get('selector', {'matchLabels': {'type': 'local-storage'}}) }}
#     - require:
#       - k8s_helm: install_openldap_ha
