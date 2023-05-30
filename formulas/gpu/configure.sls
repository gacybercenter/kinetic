include:
  - /formulas/compute/configure

{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if pillar['gpu']['backend'] == "cyborg" %}
gpu-conf-files:
  file.managed:
    - template: jinja
    - defaults:
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='cyborg', database='cyborg') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
        auth_strategy: auth_strategy = keystone
        auth_type: auth_type = password
        auth_version: auth_version = v3
        auth_protocol: auth_protocol = https
        password: {{ pillar['cyborg']['cyborg_service_password'] }}
        api: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        placement_password: {{ pillar['placement']['placement_service_password'] }}
        nova_password: {{ pillar['nova']['nova_service_password'] }}
        mdev_type: {{ pillar['hosts']['gpu']['mdev_type'][0] }}
        busid: {{ constructor.gpu_busid_constructor() }}
    - names:
      - /etc/cyborg/cyborg.conf:
        - source: salt://formulas/gpu/files/cyborg.conf
      - /etc/nova/nova-compute.conf:
        - source: salt://formulas/gpu/files/nova-compute.conf

/etc/sudoers.d/cyborg_sudoers:
  file.managed:
    - source: salt://formulas/gpu/files/cyborg_sudoers

/etc/systemd/system/cyborg-agent.service:
  file.managed:
    - source: salt://formulas/gpu/files/cyborg-agent.service
    - require:
      - sls: /formulas/gpu/install

nvidia_vgpud_service:
  service.enabled:
    - name: nvidia-vgpud.service

nvidia_vgpu_mgr:
  service.running:
    - name: nvidia-vgpu-mgr.service
    - enable: true

cyborg_agent_service:
  service.running:
    - name: cyborg-agent
    - enable: true
    - watch:
      - file: /etc/cyborg/cyborg.conf

{% endif %}

{% if pillar['gpu']['backend'] == "pci-passthrough" %}
pci_passthrough_files:
  file.managed:
    - user: root
    - group: root
    - mode: '0644'
    - template: jinja
    - defaults:
        kernel_param: {{ pillar['hosts']['gpu']['kernel_param'][0] }}
        busid_gpu1: {{ pillar['hosts']['gpu']['busid_gpu'][0] }}
        busid_gpu2: {{ pillar['hosts']['gpu']['busid_gpu'][1] }}
        busid_gpu3: {{ pillar['hosts']['gpu']['busid_gpu'][2] }}
        busid_gpu4: {{ pillar['hosts']['gpu']['busid_gpu'][3] }}
        gpu_vendor_id: {{ pillar['hosts']['gpu']['gpu_vendor_id'][0] }}
        gpu_product_id: {{ pillar['hosts']['gpu']['gpu_product_id'][0] }}
    - names:
      - /etc/default/grub.d/10-pci-passthrough.cfg:
        - source: salt://formulas/gpu/files/10-pci-passthrough.cfg
      - /etc/initramfs-tools/scripts/init-top/vfio.sh:
        - source: salt://formulas/gpu/files/vfio.sh

update-grub:
  cmd.run:
    - onchanges:
      - file: /etc/default/grub.d/10-pci-passthrough.cfg

update-initramfs -u -k all:
  cmd.run:
    - onchanges:
      - file: /etc/initramfs-tools/scripts/init-top/vfio.sh

{% endif %}
