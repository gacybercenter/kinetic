{% set k8s = salt['pillar.get']('k8s') %}
{% set rook_data = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': k8s}) %}
{% set rook = rook_data.get('rook') %}
{% set devices = rook.get('osd_mappings').get('storage').get('osd') %}
{% set namespace = rook.get('namespace') %}
{% set rook_version = rook.get('rook_version') %}
{% set ceph_image = rook.get('ceph_image') %}
{% set limits_cpu = rook.get('resources').get('limits').get('cpu') %}
{% set limits_memory = rook.get('resources').get('limits').get('memory') %}
{% set requests_cpu = rook.get('resources').get('requests').get('cpu') %}
{% set requests_memory = rook.get('resources').get('requests').get('memory') %}
{% set rook_role = rook.get('mon').get('node_role') %}
{% set rook_osd_role = rook.get('osd').get('node_role') %}

debug_join_params_{{ k8s }}:
  cmd.run:
    - name: echo "{{ namespace }}"
    - tgt: '{{ k8s }}'
    - output_loglevel: debug

k8s_deps_{{ k8s }}:
  salt.state:
    - tgt: '{{ k8s }}' 
    - sls: /formulas/common/k8s-rook/cluster
    - require:
      - cmd: debug_join_params_{{ k8s }}

# Step 1: Ensure Helm is installed on the target node
ensure_helm_installed:
  salt.state:
    - tgt: '{{ k8s }}'
    - sls: /formulas/common/helm/install
    - require:
      - salt: k8s_deps_{{ k8s }}

# Step 2: Add the rook-ceph Helm repository
add_rook_helm_repo:
  helm.repo:
    - name: rook-ceph
    - url: https://charts.rook.io/release
    - update: True
    - tgt: '{{ k8s }}'
    - require:
      - salt: ensure_helm_installed

# Step 3: Install or upgrade rook-ceph-cluster using Helm state with key-value flags
helm_install_rook_ceph_cluster:
  helm.released_present:
    - name: rook-ceph-cluster
    - chart: rook-ceph/rook-ceph-cluster
    - namespace: {{ namespace }}
    - version: {{ rook_version }}
    - create_namespace: True
    - flags:
      - dry-run
    - wait: True
    - timeout: 300
    - kvflags:
        # Core Rook Ceph Cluster settings (adjust as needed based on your requirements)
        cephClusterSpec.image: {{ ceph_image }}
        cephClusterSpec.resources.limits.cpu: {{ limits_cpu }}
        cephClusterSpec.resources.limits.memory: {{ limits_memory }}
        cephClusterSpec.resources.requests.cpu: {{ requests_cpu }}
        cephClusterSpec.resources.requests.memory: {{ requests_memory }}
        cephClusterSpec.storage.useAllNodes: false
        cephClusterSpec.storage.useAllDevices: false
        # Explicitly specify disks for OSDs from pillar data
        {% if devices %}
        {% for idx, device in devices | enumerate %}
        cephClusterSpec.storage.devices[{{ idx }}].name: "{{ device }}"
        {% endfor %}
        {% else %}
        # Fallback to an empty list if no devices are provided
        cephClusterSpec.storage.devices: []
        {% endif %}
        # Enable specific Ceph features (based on values.yaml defaults)
        cephClusterSpec.enableCephFS: false
        cephClusterSpec.enableRBD: true
        cephClusterSpec.enableRGW: true
        # Dashboard settings
        cephClusterSpec.dashboard.enabled: true
        cephClusterSpec.dashboard.urlPrefix: "/"
        # Monitoring settings
        cephClusterSpec.monitoring.enabled: true
        # Node selection for general components (optional, can be customized via pillar if needed)
        cephClusterSpec.placement.all.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key: "role"
        cephClusterSpec.placement.all.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator: "In"
        cephClusterSpec.placement.all.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]: {{ rook_role }}
        # Node selection specifically for OSDs to target rook-osd-node role
        cephClusterSpec.placement.osd.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key: "role"
        cephClusterSpec.placement.osd.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator: "In"
        cephClusterSpec.placement.osd.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]: {{ rook_osd_role }}
    - tgt: '{{ k8s }}'
    - require:
      - helm: add_rook_helm_repo