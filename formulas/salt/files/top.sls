base:
  'salt':
    - openstack
  'compute*':
    - ceph
    - nova
    - neutron
    - rabbitmq
    - placement
    - keystone
  'storage*':
    - ceph
    - keystone
  'cephmon*':
    - ceph
    - keystone
  'mysql*':
    - mysql
    - keystone
    - glance
    - nova
    - placement
    - neutron
    - heat
    - cinder
    - designate
    - swift
    - zun
  'rabbitmq*':
    - rabbitmq
  'graylog*':
    - graylog
  'keystone*':
    - keystone
    - openstack
  'glance*':
    - glance
    - openstack
    - keystone
    - ceph
  'nova*':
    - nova
    - openstack
    - rabbitmq
    - placement
    - neutron
  'placement*':
    - placement
    - openstack
    - rabbitmq
  'neutron*':
    - neutron
    - openstack
    - rabbitmq
    - nova
    - designate
  'heat*':
    - heat
    - openstack
    - rabbitmq
  'cinder*':
    - cinder
    - openstack
    - rabbitmq
    - keystone
    - ceph
  'designate*':
    - designate
    - openstack
    - rabbitmq
  'swift*':
    - swift
    - openstack
    - ceph
    - keystone
  'zun*':
    - zun
    - openstack
    - rabbitmq
    - keystone
  'container*':
    - zun
    - openstack
    - rabbitmq
    - keystone
    - neutron
