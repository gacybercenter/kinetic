#!/bin/bash

# These are the Core OpenSTack Services used in Kinetic
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"volume"}'; salt-key -d 'volume*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"heat"}'; salt-key -d 'heat*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"swift"}'; salt-key -d 'swift*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"designate"}'; salt-key -d 'designate*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"cinder"}'; salt-key -d 'cinder*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"horizon"}' ; salt-key -d 'horizon*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"neutron"}' ; salt-key -d 'neutron*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"nova"}' ; salt-key -d 'nova*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"glance"}' ; salt-key -d 'glance*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"keystone"}' ; salt-key -d 'keystone*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"bind"}' ; salt-key -d 'bind*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"rabbitmq"}' ; salt-key -d 'rabbitmq*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"memcached"}' ; salt-key -d 'memcached*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"mysql"}' ; salt-key -d 'mysql*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"etcd"}' ; salt-key -d 'etcd*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"cinder"}'; salt-key -d 'cinder*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"network"}'; salt-key -d 'network*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"guacamole"}'; salt-key -d 'guacamole*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"placement"}'; salt-key -d 'placement*' -y


salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"haproxy"}'; salt-key -d 'haproxy*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"cache"}'; salt-key -d 'cache*' -y

# These are the optional OpenStack Services used in Kinetic
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"mds"}' ; salt-key -d 'mds*' -y
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"zun"}'; salt-key -d 'zun*' -y


# If using network-ovn as the network backend, the ovsdb node needs to be zeroized, otherwise disregard
salt 'controller*' state.apply /orch/states/virtual_zero pillar='{"type":"ovsdb"}' ; salt-key -d 'ovsdb*' -y