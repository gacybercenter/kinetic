include:
  - /formulas/neutron/install
  - formulas/common/base
  - formulas/common/networking

make_neutron_service:
  cmd.script:
    - source: salt://formulas/neutron/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        neutron_internal_endpoint: {{ pillar ['openstack_services']['neutron']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['neutron']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['neutron']['configuration']['internal_endpoint']['path'] }}
        neutron_public_endpoint: {{ pillar ['openstack_services']['neutron']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['neutron']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['neutron']['configuration']['public_endpoint']['path'] }}
        neutron_admin_endpoint: {{ pillar ['openstack_services']['neutron']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['neutron']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['neutron']['configuration']['admin_endpoint']['path'] }}
        neutron_service_password: {{ pillar ['neutron']['neutron_service_password'] }}


