include:
  - /formulas/common/k8s/install

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
crio-registries:
  file.managed:
    - name: /etc/containers/registries.conf.d/crio.conf
    - makedirs: true
    - source: salt://formulas/common/k8s/files/registries.conf.j2
    - template: jinja

crio-service:
  service.running:
    - name: cri-o.service
    - enable: true
    - watch:
      - file: crio-registries
containerd-service.dead:
  service.running:
    - name: containerd.service
    - enable: true

{% for sysctl in pillar['k8s_sysctl'] %}
{{ sysctl.name }}_k8s_sysctl:
  sysctl.present:
    - name: {{ sysctl.name }}
    - value: {{ sysctl.value }}
{% endfor %}

{% for mod in pillar['k8s_modules'] %}
{{ mod }}_add_kvm:
  kmod.present:
    - name: {{ mod }}
{% endfor %}
