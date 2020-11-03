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
/etc/salt/minion.d/gitfs_remotes.conf:
  file.managed:
    - contents: |
        gitfs_remotes:
          - {{ pillar['kinetic_remote_configuration']['url'] }}:
            - saltenv:
              - base:
                - ref: {{ pillar['kinetic_remote_configuration']['branch'] }}
EOF

salt-call --local state.apply initialize
salt-call --local state.apply bootstrap
