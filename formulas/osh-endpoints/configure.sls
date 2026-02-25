include:
  - /formulas/osh-endpoints/install

# Create namespace for OpenStack public endpoint (if not already created by NGINX controller)
openstack_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar.get('nginx_ingress_namespace', 'openstack') }}

# Apply labels to nodes based on osh_labels pillar data
{% set osh_labels = pillar.get('osh_labels', {}) %}
{% if osh_labels %}
{% for label_key, nodes in osh_labels.items() %}
{% for node in nodes %}
apply_label_{{ label_key }}_to_{{ node }}:
  k8s.node_label_present:
    - namespace: unused-namespace
    - node_name: {{ node }}
    - labels:
        {{ label_key }}: enabled
{% endfor %}
{% endfor %}
{% else %}
no_osh_labels:
  test.nop:
    - comment: "No osh_labels found in pillar data. Skipping node labeling."
{% endif %}
