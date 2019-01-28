include:
  - /formulas/pxe/install

apache2_service:
  service.running:
    - name: apache2

https://git.ipxe.org/ipxe.git:
  git.latest:
    - target: /var/www/html/ipxe
    - require:
      - sls: /formulas/pxe/install

/var/www/html/ipxe/src/kinetic.ipxe:
  file.managed:
    - source: salt://formulas/pxe/files/kinetic.ipxe

create_efi_module:
  cmd.run:
    - name: |
        make bin-x86_64-efi/ipxe.efi EMBED=kinetic.ipxe && cp bin-x86_64-efi/ipxe.efi /srv/tftp/
    - cwd: /var/www/html/ipxe/src/
    - creates: /srv/tftp/ipxe.efi

php7.2_module:
  apache_module.enabled:
    - name: php7.2

/var/www/html/index.html:
  file.absent

/var/www/html/pending_hosts:
  file.directory:
    - user: www-data
    - group: www-data

/var/www/html/hosts:
  file.managed:
    - contents: |
      {% for type, macs in salt['pillar.get']('hosts', {}).items() %}
        {% for mac in pillar['hosts'][type]['macs'] %}
          {{ mac }} = {{ type }}
        {%- endfor %}
      {% endfor %}

/var/www/html/index.php:
  file.managed:
    - source: salt://formulas/pxe/files/index.php

/var/www/html/common.pxe:
  file.managed:
    - source: salt://formulas/pxe/files/common.pxe

{% for type in pillar['hosts'] %}
/var/www/html/preseed/{{ type }}.preseed:
  file.managed:
    - source: salt://formulas/pxe/files/common.preseed
    - makedirs: True
    - template: jinja
    - defaults:
        proxy: {{ pillar['hosts'][type]['proxy'] }}
        root_password_crypted: {{ pillar['hosts'][type]['root_password_crypted'] }}
        zone: {{ pillar['timezone'] }}
        ntp_server: {{ pillar['hosts'][type]['ntp_server'] }}
        disk: {{ pillar['hosts'][type]['disk'] }}
        method: {{ pillar['hosts'][type]['partman_config']['method'] }}
        type:{{ pillar['hosts'][type]['partman_config']['type'] }}
        interface: {{ pillar['hosts'][type]['interface'] }}
        expert_recipe: |
          {%- if pillar['hosts'][type]['partman_config']['method'] == raid %}
          d-i partman-auto/expert_recipe string             \
              efi-lvm ::                                    \
                  256 10 256 fat32                          \
                  \$primary{ }                              \
                  \$lvmignore{ }                            \
                  method{ efi }                             \
                  format{ }                                 \
                  .                                         \
                  65536 30 -1 raid                          \
                  \$lvmignore{ }                            \
                  \$primary{ }                              \
                  method{ raid }                            \
                  .                                         \
                  65536 50 -1 ext4                          \
                  \$defaultignore{ }                        \
                  \$lvmok{ }                                \
                  lv_name{ rootfs }                         \
                  method{ format }                          \
                  format{ }                                 \
                  use_filesystem{ }                         \
                  filesystem{ ext4 }                        \
                  mountpoint{ / }                           \
                  label{ Root }                             \
                  .                                         \
                  8192 40 8192 swap                         \
                  \$defaultignore{ }                        \
                  \$lvmok{ }                                \
                  lv_name{ swap }                           \
                  method{ swap }                            \
                  format{ }                                 \
                  .
          d-i partman-auto-raid/recipe string               \
              {{ pillar['hosts'][type]['partman_config']['type'] }} {{ pillar['hosts'][type]['partman_config']['count'] }} {{ pillar['hosts'][type]['partman_config']['spares'] }} lvm - {{ pillar['hosts'][type]['partman_config']['disks'] }} \
              .
          {$- else %}
          d-i partman-auto/expert_recipe string             \
              efi-lvm-bigram ::                             \
                  538 538 1075 free                         \
                  $iflabel{ gpt }                           \
                  $reusemethod{ }                           \
                  method{ efi }                             \
                  format{ }                                 \
                  .                                         \
              128 512 256 ext2                              \
                  $defaultignore{ }                         \
                  method{ format }                          \
                  format{ }                                 \
                  use_filesystem{ }                         \
                  filesystem{ ext2 }                        \
                  mountpoint{ /boot }                       \
                  .                                         \
              512 10000 -1 $default_filesystem              \
                  $lvmok{ }                                 \
                  method{ format }                          \
                  format{ }                                 \
                  use_filesystem{ }                         \
                  $default_filesystem{ }                    \
                  mountpoint{ / }                           \
                  .                                         \
              8192 512 8192 linux-swap                      \
                  $lvmok{ }                                 \
                  $reusemethod{ }                           \
                  method{ swap }                            \
                  format{ }                                 \
                  .
          {% endif %}
{% if pillar['hosts'][type]['proxy'] == 'pull_from_mine' %}
    - context:
{% set cache_addresses_dict = salt['mine.get']('cache*','network.ip_addrs') %}
{% if cache_addresses_dict == {} %}
        proxy: ""
{% else %}
{% for host in cache_addresses_dict %}
        proxy: http://{{ cache_addresses_dict[host][0] }}:3142
{% endfor %}
{% endif %}
{% endif %}
{% endfor %}
