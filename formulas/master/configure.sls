include:
  - /formulas/master/install

modules_load_k8s_file:
  file.managed:
    - name: /etc/modules-load.d/k8s.conf
    - content: |
        overlay
        br_netfilter
sysctl_k8s_file:
  file.managed:
    - name: /etc/sysctl.d/k8s.conf
    - content: |
        net.bridge.bridge-nf-call-ip6tables = 1
        net.bridge.bridge-nf-call-iptables = 1
        net.ipv4.ip_forward = 1

{% for sysctl in pillar['k8s_sysctl'].items() %}
{{ sysctl }}_k8s_sysctl:
  sysctl.present:
    - name: {{ sysctl }}
    - value: {{ pillar['k8s_sysctl'][sysctl] }}
{% endfor %}

{% for mod in pillar['k8s_modules'] %}
{{ mod }}_add_kvm:
  kmod.present:
    - name: {{ mod }}
{% endfor %}