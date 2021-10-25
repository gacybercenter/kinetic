## Copyright 2019 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

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
    - guacamole
    - integrated_services
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
    - openstack
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
    - openstack
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
  'guacamole*':
    - guacamole
    - integrated_services
