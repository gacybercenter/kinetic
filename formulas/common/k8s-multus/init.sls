include:
  - /formulas/common/k8s-multus/install

# Ensure the Multus Helm repository is available
ensure_multus_helm_repo:
  k8s_helm.helm_repo_present:
    - repo_name: k8snetworkplumbingwg
    - repo_url: https://raw.githubusercontent.com/k8snetworkplumbingwg/helm-charts/main/charts
    - update_cache: true

# Deploy Multus using the new k8s_helm state with pillar_key
ensure_multus_release:
  k8s_helm.helm_release_present:
    - release_name: multus
    - chart_name: k8snetworkplumbingwg/multus-cni
    - namespace: kube-system
    - pillar_key: res-k8s:multus:values
    - wait_timeout: 300
    - wait_interval: 10
    - require:
      - k8s_helm: ensure_multus_helm_repo

# Create standard network attachments for SFE and SBE networks
sfe_network_attachment:
  k8s.networkattachmentdefinition_present:
    - name: sfe
    - namespace: default
    - cidr: 10.150.2.0/24
    - range_start: 10.150.2.10
    - range_end: 10.150.2.254
    - require:
      - k8s_helm: ensure_multus_release

sbe_network_attachment:
  k8s.networkattachmentdefinition_present:
    - name: sbe
    - namespace: default
    - cidr: 10.150.3.0/24
    - range_start: 10.150.3.10
    - range_end: 10.150.3.254
    - require:
      - k8s: sfe_network_attachment
