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
    - swift
  'storage*':
    - ceph
    - swift
  'cephmon*':
    - ceph
    - swift
  'etcd*':
    - etcd
  'mds*':
    - ceph
    - swift
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
    - swift
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
    - ceph
  'volume*':
    - cinder
    - rabbitmq
    - swift
    - ceph
  'manila*':
    - manila
    - rabbitmq
  'share*':
    - manila
    - rabbitmq
    - swift
    - ceph
  'designate*':
    - designate
    - rabbitmq
  'bind*':
    - designate
  'swift*':
    - swift
    - ceph
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
