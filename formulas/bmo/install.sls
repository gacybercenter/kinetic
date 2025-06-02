# /srv/salt/bmo_ironic_kubevip_helm.sls

# Ensure Helm is installed
helm_installed:
  cmd.run:
    - name: helm version --short
    - unless: test -f /usr/local/bin/helm

# Create namespace for Baremetal Operator, Ironic, and kube-vip (if it doesn't exist)
bmo_ironic_namespace:
  cmd.run:
    - name: kubectl create namespace {{ pillar['bmo_namespace'] }} --dry-run=client -o yaml | kubectl apply -f -
    - unless: kubectl get namespace {{ pillar['bmo_namespace'] }}
    - require:
      - cmd: helm_installed

# Create Secret for Ironic basic auth credentials
ironic_auth_secret:
  kubernetes.secret_present:
    - name: {{ pillar['ironic_auth_secret_name'] }}
    - namespace: {{ pillar['bmo_namespace'] }}
    - data:
        username: {{ pillar['ironic_auth_username'] | b64encode }}
        password: {{ pillar['ironic_auth_password'] | b64encode }}
    - require:
      - cmd: bmo_ironic_namespace

# Add Metal³ Helm repository
metal3_helm_repo:
  helm.repo_managed:
    - name: metal3
    - url: {{ pillar['bmo_helm_repo_url'] }}
    - require:
      - cmd: helm_installed

# Install or upgrade Baremetal Operator and Ironic Helm release
bmo_ironic_helm_release:
  helm.release_present:
    - name: {{ pillar['bmo_release_name'] }}
    - chart: metal3/baremetal-operator
    - namespace: {{ pillar['bmo_namespace'] }}
    - version: {{ pillar['bmo_chart_version'] }}
    - values: {{ pillar['bmo_helm_values'] | tojson }}
    - update: True
    - require:
      - helm: metal3_helm_repo
      - cmd: bmo_ironic_namespace
      - kubernetes: ironic_auth_secret