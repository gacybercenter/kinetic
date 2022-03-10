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

openstack_services:
  keystone:
    configuration:
      dbs:
        - keystone
      services:
        keystone:
          type: identity
          description: OpenStack Identity Service
          endpoints:
            internal:
              protocol: "https://"
              port: ":5000"
              path: /v3
            admin:
              protocol: "https://"
              port: ":5000"
              path: /v3
            public:
              protocol: "https://"
              port: ":5000"
              path: /v3
  glance:
    configuration:
      dbs:
        - glance
      services:
        glance:
          type: image
          description: OpenStack Image Service
          endpoints:
            internal:
              protocol: "https://"
              port: ":9292"
              path: /
            admin:
              protocol: "https://"
              port: ":9292"
              path: /
            public:
              protocol: "https://"
              port: ":9292"
              path: /
  barbican:
    configuration:
      dbs:
        - barbican
      services:
        barbican:
          type: key-manager
          description: OpenStack Key Manager Service
          endpoints:
            internal:
              protocol: "https://"
              port: ":9311"
              path: /
            admin:
              protocol: "https://"
              port: ":9311"
              path: /
            public:
              protocol: "https://"
              port: ":9311"
              path: /
  nova:
    configuration:
      dbs:
        - nova
        - nova_api
        - nova_cell0
      services:
        nova:
          type: compute
          description: OpenStack Compute Service
          endpoints:
            internal:
              protocol: "https://"
              port: ":8774"
              path: /v2.1/
            admin:
              protocol: "https://"
              port: ":8774"
              path: /v2.1/
            public:
              protocol: "https://"
              port: ":8774"
              path: /v2.1/
  placement:
    configuration:
      dbs:
        - placement
      services:
        placement:
          type: placement
          description: OpenStack Placement Service
          endpoints:
            internal:
              protocol: "https://"
              port: ":8778"
              path: /
            admin:
              protocol: "https://"
              port: ":8778"
              path: /
            public:
              protocol: "https://"
              port: ":8778"
              path: /
  neutron:
    configuration:
      dbs:
        - neutron
      services:
        neutron:
          type: network
          description: OpenStack Networking Service
          endpoints:
            internal:
              protocol: "https://"
              port: ":9696"
              path: /
            admin:
              protocol: "https://"
              port: ":9696"
              path: /
            public:
              protocol: "https://"
              port: ":9696"
              path: /
  heat:
    configuration:
      dbs:
        - heat
      services:
        heat:
          type: orchestration
          description: OpenStack Orchestration Service
          endpoints:
            internal:
              protocol: "https://"
              port: ":8004"
              path: /v1/%(tenant_id)s
            admin:
              protocol: "https://"
              port: ":8004"
              path: /v1/%(tenant_id)s
            public:
              protocol: "https://"
              port: ":8004"
              path: /v1/%(tenant_id)s
        heat-cfn:
          type: cloudformation
          description: OpenStack Cloudformation Service
          endpoints:
            internal:
              protocol: "https://"
              port: ":8000"
              path: /v1
            admin:
              protocol: "https://"
              port: ":8000"
              path: /v1
            public:
              protocol: "https://"
              port: ":8000"
              path: /v1
  cinder:
    configuration:
      dbs:
        - cinder
      services:
        cinderv2:
          type: volumev2
          description: OpenStack Block Storage Service v2
          endpoints:
            internal:
              protocol: "https://"
              port: ":8776"
              path: /v2/%(project_id)s
            admin:
              protocol: "https://"
              port: ":8776"
              path: /v2/%(project_id)s
            public:
              protocol: "https://"
              port: ":8776"
              path: /v2/%(project_id)s
        cinderv3:
          type: volumev3
          description: OpenStack Block Storage Service v3
          endpoints:
            internal:
              protocol: "https://"
              port: ":8776"
              path: /v3/%(project_id)s
            admin:
              protocol: "https://"
              port: ":8776"
              path: /v3/%(project_id)s
            public:
              protocol: "https://"
              port: ":8776"
              path: /v3/%(project_id)s
  designate:
    configuration:
      dbs:
        - designate
      services:
        designate:
          type: dns
          description: OpenStack DNS Service
          endpoints:
            public:
              protocol: "https://"
              port: ":9001"
              path: /
  swift:
    configuration:
      services:
        swift:
          type: object-store
          description: OpenStack Object Storage Service
          endpoints:
            internal:
              protocol: "https://"
              port: ":7480"
              path: /swift/v1/AUTH_%(project_id)s
            admin:
              protocol: "https://"
              port: ":7480"
              path: /swift/v1/AUTH_%(project_id)s
            public:
              protocol: "https://"
              port: ":7480"
              path: /swift/v1/AUTH_%(project_id)s
  zun:
    configuration:
      dbs:
        - zun
      services:
        zun:
          type: container
          description: OpenStack Container Service
          endpoints:
            internal:
              protocol: "https://"
              port: ":9517"
              path: /v1
            admin:
              protocol: "https://"
              port: ":9517"
              path: /v1
            public:
              protocol: "https://"
              port: ":9517"
              path: /v1
  magnum:
    configuration:
      dbs:
        - magnum
      services:
        magnum:
          type: container-infra
          description: OpenStack Container Infrastructure Management Service
          endpoints:
            internal:
              protocol: "https://"
              port: ":9511"
              path: /v1
            admin:
              protocol: "https://"
              port: ":9511"
              path: /v1
            public:
              protocol: "https://"
              port: ":9511"
              path: /v1
  sahara:
    configuration:
      dbs:
        - sahara
      services:
        sahara:
          type: data-processing
          description: OpenStack Data Processing Service
          endpoints:
            internal:
              protocol: "https://"
              port: ":8386"
              path: /v1.1/%(project_id)s
            admin:
              protocol: "https://"
              port: ":8386"
              path: /v1.1/%(project_id)s
            public:
              protocol: "https://"
              port: ":8386"
              path: /v1.1/%(project_id)s
  manila:
    configuration:
      dbs:
        - manila
      services:
        manila:
          type: share
          description: OpenStack Shared File Systems Service
          endpoints:
            internal:
              protocol: "https://"
              port: ":8786"
              path: /v1/%(project_id)s
            admin:
              protocol: "https://"
              port: ":8786"
              path: /v1/%(project_id)s
            public:
              protocol: "https://"
              port: ":8786"
              path: /v1/%(project_id)s
        manilav2:
          type: sharev2
          description: OpenStack Shared File Systems Service v2
          endpoints:
            internal:
              protocol: "https://"
              port: ":8786"
              path: /v2/%(project_id)s
            admin:
              protocol: "https://"
              port: ":8786"
              path: /v2/%(project_id)s
            public:
              protocol: "https://"
              port: ":8786"
              path: /v2/%(project_id)s
  octavia:
    configuration:
      dbs:
        - octavia
        - octavia_persistence
      services:
        octavia:
          type: load-balancer
          description: OpenStack Octavia
          endpoints:
            internal:
              protocol: "https://"
              port: ":9876"
              path: /
            admin:
              protocol: "https://"
              port: ":9876"
              path: /
            public:
              protocol: "https://"
              port: ":9876"
              path: /