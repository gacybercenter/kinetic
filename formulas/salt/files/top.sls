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
  'etcd*':
    - etcd
  'mds*':
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
    - barbican
    - magnum
    - sahara
    - manila
  'rabbitmq*':
    - rabbitmq
  'graylog*':
    - graylog
  'keystone*':
    - keystone
    - openstack
  'barbican*':
    - barbican
    - openstack
    - keystone
    - rabbitmq
  'magnum*':
    - magnum
    - openstack
    - keystone
    - rabbitmq
  'sahara*':
    - sahara
    - openstack
    - keystone
    - rabbitmq
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
  'network*':
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
  'manila*':
    - manila
    - openstack
    - rabbitmq
    - keystone
    - ceph
  'share*':
    - manila
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
  'horizon*':
    - horizon
