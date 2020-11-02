## Copyright 2018 Augusta University
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

if  [ "$(id -u)" -ne 0 ];
then
   echo "Please run this script as the root user or with sudo"
   exit
fi

if ! which curl > /dev/null;
then
  echo "Please install cURL and make sure it is available in your path"
  exit
fi

if [ $# -lt 2 ]; then
  echo 1>&2 "$0: not enough arguments"
  exit 2
fi

while getopts ":a:" opt; do
  case ${opt} in
    a )
      answers=$OPTARG
      ;;
    \? )
      echo "Invalid option: $OPTARG." 1>&2
      exit
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      exit
      ;;
  esac
done

## create file and pillar root
mkdir -p /srv/salt /srv/pillar

## install masterless salt minion
curl -L -o /tmp/bootstrap_salt.sh https://bootstrap.saltstack.com
/bin/sh /tmp/bootstrap_salt.sh

## configure masterless minion
echo "file_client: local" > /etc/salt/minion.d/file_client.conf
echo "fileserver_backend: [roots, git]" > /etc/salt/minion.d/fileserver_backend.conf
echo "pillar_roots: { base: [/srv/pillar] }" > /etc/salt/minion.d/pillar_roots.conf
echo "base: {'*': [answers]}" > /srv/pillar/top.sls

## pull down specified answer file
curl -L -o /srv/pillar/answers.sls $answers

## set up bootstrap.sls execution
cat << EOF > /srv/salt/initialize.sls
/etc/salt/minion.d/gitfs_remotes.cfg:
  file.managed:
    - contents: |
        gitfs_remotes:
          - {{ pillar['kinetic_remote_configuration']['url'] }}:
            - saltenv:
              - base:
                - ref: {{ pillar['kinetic_remote_configuration']['branch'] }}
EOF

salt-call --local state.apply initialize
salt-call --local service.restart salt-minion
salt-call --local state.apply bootstrap/resources/bootstrap

# ## Packages
# apt-get update
# apt-get -y dist-upgrade
# apt-get -y install qemu-kvm qemu-utils genisoimage curl libvirt-clients libvirt-daemon-system
#
# ## Directories
#
# mkdir -p /kvm/images
# mkdir -p /kvm/vms/salt/data
# mkdir -p /kvm/vms/pxe/data
#
# ## kernel configuration
# if $(lscpu | grep -q GenuineIntel)
# then
#   /usr/sbin/modprobe -r kvm_intel
#   echo options kvm_intel nested=1 > /etc/modprobe.d/kvm.conf
#   /usr/sbin/modprobe kvm_intel nested=1
# elif $(lscpu | grep -q AuthenticAMD)
# then
#   /usr/sbin/modprobe -r kvm_amd
#   echo options kvm_amd nested=1 > /etc/modprobe.d/kvm.conf
#   /usr/sbin/modprobe kvm_amd nested=1
# fi
#
# ## Images
#
# if [ ! -f /kvm/images/debian10.raw ]
# then
#   local_image_hash=bad
# else
#   local_image_hash=$(sha512sum /kvm/images/debian10.raw | awk '{ print $1 }')
# fi
#
# remote_image_hash=$(curl https://cdimage.debian.org/cdimage/openstack/current-10/SHA512SUMS | grep $local_image_hash | awk '{ print $1 }')
#
# if [ "$local_image_hash" == "$remote_image_hash" ]
# then
#   echo No new image needed.  Skipping download.
# else
#   echo Image hash mismatch.  Re-downloading.
#   wget https://cdimage.debian.org/cdimage/openstack/current-10/debian-10-openstack-amd64.raw -O /kvm/images/debian10.raw
# fi
#
#
# ## salt
# if [ ! -f /kvm/vms/salt/disk0.raw ]
# then
#   cp /kvm/images/debian10.raw /kvm/vms/salt/disk0.raw
#   qemu-img resize -f raw /kvm/vms/salt/disk0.raw 8G
# fi
#
# curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.xml | sed "s/{{ name }}/salt/g; s/{{ interface }}/$interface/g; s/{{ ram }}/8192000/g; s/{{ cpu }}/6/g" > /kvm/vms/salt/config.xml
# curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.metadata | sed "s/{{ name }}/salt/g" > /kvm/vms/salt/data/meta-data
# curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.userdata | sed "s%{{ opts }}%-M -x python3 -X -i salt -J \'{ \"default_top\": \"base\", \"fileserver_backend\": [ \"git\" ], \"ext_pillar\": [ { \"git\": [ { \"$pillar_branch $pillar\": [ { \"env\": \"base\" } ] } ] } ], \"ext_pillar_first\": true, \"gitfs_remotes\": [ { \"$fileroot\": [ { \"saltenv\": [ { \"base\": [ { \"ref\": \"$fileroot_branch\" } ] } ] } ] } ], \"gitfs_saltenv_whitelist\": [ \"base\" ] }\'%g;s%{{ key }}%$key%g" > /kvm/vms/salt/data/user-data
# sed -i "s,{{ extra_commands }},mkdir -p /etc/salt/gpgkeys;chmod 0700 /etc/salt/gpgkeys;curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/key-generation | gpg --expert --full-gen-key --homedir /etc/salt/gpgkeys/ --batch;gpg --export --homedir /etc/salt/gpgkeys -a > /root/key.gpg,g" /kvm/vms/salt/data/user-data
# genisoimage -o /kvm/vms/salt/config.iso -V cidata -r -J /kvm/vms/salt/data/meta-data /kvm/vms/salt/data/user-data
# virsh create /kvm/vms/salt/config.xml
#
# ##pxe
# if [ ! -f /kvm/vms/pxe/disk0.raw ]
# then
#   cp /kvm/images/debian10.raw /kvm/vms/pxe/disk0.raw
#   qemu-img resize -f raw /kvm/vms/pxe/disk0.raw 8G
# fi
# curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.xml | sed "s/{{ name }}/pxe/g; s/{{ interface }}/$interface/g; s/{{ ram }}/2048000/g; s/{{ cpu }}/1/g" > /kvm/vms/pxe/config.xml
# curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.metadata | sed "s/{{ name }}/pxe/g" > /kvm/vms/pxe/data/meta-data
# curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.userdata | sed "s/{{ opts }}/-X -x python3 -i pxe/g;s/{{ key }}/$key/g" > /kvm/vms/pxe/data/user-data
# sed -i "s,{{ extra_commands }},echo No extra commands specified,g" /kvm/vms/pxe/data/user-data
# genisoimage -o /kvm/vms/pxe/config.iso -V cidata -r -J /kvm/vms/pxe/data/meta-data /kvm/vms/pxe/data/user-data
# virsh create /kvm/vms/pxe/config.xml
