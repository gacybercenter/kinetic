base:
  '*':
    - api
    - deps
  'salt':
    - openstack
  'cache*':
    - cache
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
    - rabbitmq
  'magnum*':
    - magnum
    - openstack
    - rabbitmq
  'sahara*':
    - sahara
    - openstack
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
  'volume*':
    - cinder
    - openstack
    - rabbitmq
    - keystone
    - ceph
  'manila*':
    - manila
    - openstack
    - rabbitmq
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
  'bind*':
    - designate
  'swift*':
    - swift
    - openstack
    - ceph
    - keystone
  'zun*':
    - zun
    - openstack
    - rabbitmq
  'container*':
    - zun
    - openstack
    - rabbitmq
    - neutron
  'horizon*':
    - horizon
  'webssh2*':
    - webssh2
