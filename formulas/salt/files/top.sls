base:
  '*':
    - api
    - deps
    - openstack_services
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
    - barbican
    - magnum
    - sahara
    - glance
    - nova
    - placement
    - neutron
    - heat
    - cinder
    - manila
    - designate
    - swift
    - zun
    - openstack
  'barbican*':
    - barbican
    - rabbitmq
  'magnum*':
    - magnum
    - rabbitmq
  'sahara*':
    - sahara
    - rabbitmq
  'glance*':
    - glance
    - keystone
    - ceph
  'nova*':
    - nova
    - rabbitmq
    - placement
    - neutron
  'placement*':
    - placement
    - rabbitmq
  'neutron*':
    - neutron
    - rabbitmq
    - nova
    - designate
  'network*':
    - neutron
    - rabbitmq
    - nova
    - designate
  'heat*':
    - heat
    - rabbitmq
  'cinder*':
    - cinder
    - rabbitmq
    - keystone
    - ceph
  'volume*':
    - cinder
    - rabbitmq
    - keystone
    - ceph
  'manila*':
    - manila
    - rabbitmq
  'share*':
    - manila
    - rabbitmq
    - keystone
    - ceph
  'designate*':
    - designate
    - rabbitmq
  'bind*':
    - designate
  'swift*':
    - swift
    - ceph
    - keystone
  'zun*':
    - zun
    - rabbitmq
  'container*':
    - zun
    - rabbitmq
    - neutron
  'horizon*':
    - horizon
  'webssh2*':
    - webssh2
