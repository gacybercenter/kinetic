include:
  - /formulas/common/k8s-multus/install

# # Ensure the Multus Helm repository is available
# ensure_multus_helm_repo:
#   k8s_helm.helm_repo_present:
#     - repo_name: bitnami
#     - repo_url: https://charts.bitnami.com/bitnami
#     - update_cache: true

# # Deploy Multus using the new k8s_helm state with pillar_key
# ensure_multus_release:
#   k8s_helm.helm_release_present:
#     - release_name: multus
#     - chart_name: bitnami/multus-cni
#     - namespace: kube-system
#     - pillar_key: res-k8s:multus:values
#     - wait_timeout: 300
#     - wait_interval: 10
#     - require:
#       - k8s_helm: ensure_multus_helm_repo

{% set multus_version = pillar['res-k8s']['multus']['multus_version'] %}
{% set multus_manifest_url = pillar['res-k8s']['multus']['multus_manifest_url'] %}

# Apply Multus manifest (idempotent via unless check)
install_multus_manifest:
  cmd.run:
    - name: kubectl apply -f {{ multus_manifest_url }}
    - unless: |
        kubectl get daemonset kube-multus-ds -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -q "{{ multus_version }}" ||
        kubectl get daemonset kube-multus-ds -n kube-system >/dev/null 2>&1 && echo "Multus {{ multus_version }} already installed"


# Standard network attachments (SFE, SBE, PRIV, PUB) - added to multus formula
sfe_network_attachment:
  k8s.networkattachmentdefinition_present:
    - name: sfe
    - namespace: default
    - master: sfe_br
    - cidr: 10.150.2.0/24
    - range_start: 10.150.2.10
    - range_end: 10.150.2.200
    - require:
      - cmd: install_multus_manifest

sbe_network_attachment:
  k8s.networkattachmentdefinition_present:
    - name: sbe
    - namespace: default
    - master: sbe_br
    - cidr: 10.150.3.0/24
    - range_start: 10.150.3.10
    - range_end: 10.150.3.200
    - require:
      - cmd: install_multus_manifest

priv_network_attachment:
  k8s.networkattachmentdefinition_present:
    - name: priv
    - namespace: default
    - master: priv_br
    - cidr: 10.150.4.0/24
    - range_start: 10.150.4.10
    - range_end: 10.150.4.200
    - require:
      - cmd: install_multus_manifest

pub_network_attachment:
  k8s.networkattachmentdefinition_present:
    - name: pub
    - namespace: default
    - master: pub_br
    - cidr: 10.151.0.0/16
    - range_start: 10.151.0.10
    - range_end: 10.151.255.200
    - gateway: 10.151.255.254
    - require:
      - cmd: install_multus_manifest
