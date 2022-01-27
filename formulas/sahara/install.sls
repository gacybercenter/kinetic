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

include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo

{% if grains['os_family'] == 'Debian' %}

sahara_packages:
  pkg.installed:
    - pkgs:
      - apache2
      - sahara
      - sahara-api
      - sahara-engine
      - python3-saharaclient
      - python3-openstackclient
      - python3-etcd3gw

{% elif grains['os_family'] == 'RedHat' %}

sahara_packages:
  pkg.installed:
    - pkgs:
      - openstack-sahara-api
      - openstack-sahara-engine
      - openstack-sahara
      - python3-saharaclient
      - python3-openstackclient

{% endif %}

mapr_plugin_latest:
 file.directory:
   - name: /var/lib/sahara_plugin_mapr
   - user: sahara
   - group: sahara
   - mode: "0755"
   - makedirs: True
 git.latest:
   - name: https://github.com/openstack/sahara-plugin-mapr.git
   - branch: stable/xena
   - target: /var/lib/sahara_plugin_mapr
   - force_clone: True

ambari_plugin_latest:
 file.directory:
   - name: /var/lib/sahara_plugin_ambari
   - user: sahara
   - group: sahara
   - mode: "0755"
   - makedirs: True
 git.latest:
   - name: https://github.com/openstack/sahara-plugin-ambari.git
   - branch: stable/xena
   - target: /var/lib/sahara_plugin_ambari
   - force_clone: True

storm_plugin_latest:
 file.directory:
   - name: /var/lib/sahara_plugin_storm
   - user: sahara
   - group: sahara
   - mode: "0755"
   - makedirs: True
 git.latest:
   - name: https://github.com/openstack/sahara-plugin-storm.git
   - branch: stable/xena
   - target: /var/lib/sahara_plugin_storm
   - force_clone: True

cdh_plugin_latest:
 file.directory:
   - name: /var/lib/sahara_plugin_cdh
   - user: sahara
   - group: sahara
   - mode: "0755"
   - makedirs: True
 git.latest:
   - name: https://github.com/openstack/sahara-plugin-cdh.git
   - branch: stable/xena
   - target: /var/lib/sahara_plugin_cdh
   - force_clone: True

spark_plugin_latest:
 file.directory:
   - name: /var/lib/sahara_plugin_spark
   - user: sahara
   - group: sahara
   - mode: "0755"
   - makedirs: True
 git.latest:
   - name: https://github.com/openstack/sahara-plugin-spark.git
   - branch: stable/xena
   - target: /var/lib/sahara_plugin_spark
   - force_clone: True

vanilla_plugin_latest:
 file.directory:
   - name: /var/lib/sahara_plugin_vanilla
   - user: sahara
   - group: sahara
   - mode: "0755"
   - makedirs: True
 git.latest:
   - name: https://github.com/openstack/sahara-plugin-vanilla.git
   - branch: stable/xena
   - target: /var/lib/sahara_plugin_vanilla
   - force_clone: True

### Patch sahara_plugin_vanilla https://gitlab.com/gacybercenter/gacyberrange/infrastructure/kinetic/-/issues/142
vanilla_patch:
  file.managed:
    - name: /var/lib/sahara_plugin_vanilla/build/lib/sahara_plugin_vanilla/plugins/vanilla/hadoop2/run_scripts.py
    - source: salt://formulas/sahara/files/run_scripts.py
    - require:
      - git: vanilla_plugin_latest

mapr_plugin_requirements:
  cmd.run:
    - name: pip3 install -r /var/lib/sahara_plugin_mapr/requirements.txt
    - unless:
      - systemctl is-active sahara-engine
    - require:
      - git: mapr_plugin_latest

ambari_plugin_requirements:
  cmd.run:
    - name: pip3 install -r /var/lib/sahara_plugin_ambari/requirements.txt
    - unless:
      - systemctl is-active sahara-engine
    - require:
      - git: ambari_plugin_latest

storm_plugin_requirements:
  cmd.run:
    - name: pip3 install -r /var/lib/sahara_plugin_storm/requirements.txt
    - unless:
      - systemctl is-active sahara-engine
    - require:
      - git: storm_plugin_latest

cdh_plugin_requirements:
  cmd.run:
    - name: pip3 install -r /var/lib/sahara_plugin_cdh/requirements.txt
    - unless:
      - systemctl is-active sahara-engine
    - require:
      - git: cdh_plugin_latest

spark_plugin_requirements:
  cmd.run:
    - name: pip3 install -r /var/lib/sahara_plugin_spark/requirements.txt
    - unless:
      - systemctl is-active sahara-engine
    - require:
      - git: spark_plugin_latest

vanilla_plugin_requirements:
  cmd.run:
    - name: pip3 install -r /var/lib/sahara_plugin_vanilla/requirements.txt
    - unless:
      - systemctl is-active sahara-engine
    - require:
      - file: vanilla_patch

mapr_plugin_install:
  cmd.run:
    - name: python3 setup.py install
    - cwd : /var/lib/sahara_plugin_mapr
    - unless:
      - systemctl is-active sahara-engine
    - require:
      - cmd: mapr_plugin_requirements

ambari_plugin_install:
  cmd.run:
    - name: python3 setup.py install
    - cwd : /var/lib/sahara_plugin_ambari
    - unless:
      - systemctl is-active sahara-engine
    - require:
      - cmd: ambari_plugin_requirements

storm_plugin_install:
  cmd.run:
    - name: python3 setup.py install
    - cwd : /var/lib/sahara_plugin_storm
    - unless:
      - systemctl is-active sahara-engine
    - require:
      - cmd: storm_plugin_requirements

cdh_plugin_install:
  cmd.run:
    - name: python3 setup.py install
    - cwd : /var/lib/sahara_plugin_cdh
    - unless:
      - systemctl is-active sahara-engine
    - require:
      - cmd: cdh_plugin_requirements

spark_plugin_install:
  cmd.run:
    - name: python3 setup.py install
    - cwd : /var/lib/sahara_plugin_spark
    - unless:
      - systemctl is-active sahara-engine
    - require:
      - cmd: spark_plugin_requirements

vanilla_plugin_install:
  cmd.run:
    - name: python3 setup.py install
    - cwd : /var/lib/sahara_plugin_vanilla
    - unless:
      - systemctl is-active sahara-engine
    - require:
      - cmd: vanilla_plugin_requirements