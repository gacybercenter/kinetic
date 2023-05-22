## Copyright 2020 Augusta University
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

### default dependencies file

hosts:
  controller:
    needs:
      configure:
        salt: configure
        pxe: configure
  controllerv2:
    needs:
      configure:
        salt: configure
        pxe: configure
  storage:
    needs:
      install:
        cache: configure
      configure:
        cephmon: configure
        pxe: configure
  storagev2:
    needs:
      install:
        cache: configure
      configure:
        cephmon: configure
        pxe: configure
  compute:
    needs:
      install:
        cache: configure
      configure:
        nova: configure
        neutron: configure
  computev2:
    needs:
      install:
        cache: configure
      configure:
        nova: configure
        neutron: configure
  container:
    needs:
      install:
        cache: configure
      configure:
        nova: configure
        neutron: configure
        zun: configure
        etcd: configure
  cache:
    needs:
      configure:
        controller: configure
  cephmon:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
  mds:
    needs:
      install:
        cache: configure
      configure:
        cephmon: configure
        controller: configure
  haproxy:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
  mysql:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
  rabbitmq:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
  memcached:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
  keystone:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        mysql: configure
  glance:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
        storage: configure
        cephmon: configure
  nova:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
        placement: configure
  neutron:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
        {{ ovsdb }}
  network:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
        neutron: configure
  horizon:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
  heat:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
  cinder:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
        cephmon: configure
        storage: configure
  volume:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
        cinder: configure
  designate:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
        bind: configure
  bind:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
  swift:
    needs:
      install:
        cache: configure
      configure:
        cephmon: configure
        storage: configure
        keystone: configure
  zun:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
  placement:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
  opensearch:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
  ovsdb:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
  barbican:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
  magnum:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
  sahara:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
  manila:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
        cephmon: configure
        mds: configure
        storage: configure
  share:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        memcached: configure
        rabbitmq: configure
        keystone: configure
        manila: configure
        cephmon: configure
        mds: configure
        storage: configure
  etcd:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
  guacamole:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure
        mysql: configure
  jproxy:
    needs:
      install:
        cache: configure
      configure:
        controller: configure
        haproxy: configure