include:
  - /formulas/haproxy/install
  - formulas/common/base
  - formulas/common/networking

{% for domain in pillar['haproxy']['tls_domains'] %}

haproxy_{{ domain }}_service_dead:
  service.dead:
    - name: haproxy
    - prereq:
      - letsencrypt certonly -d {{ domain }} --non-interactive --standalone --agree-tos --email {{ pillar['haproxy']['tls_email'] }}

letsencrypt certonly -d {{ domain }} --non-interactive --standalone --agree-tos --email {{ pillar['haproxy']['tls_email'] }}:
  cmd.run:
    - creates:
      - /etc/letsencrypt/live/{{ domain }}/fullchain.pem
      - /etc/letsencrypt/live/{{ domain }}/privkey.pem

cat /etc/letsencrypt/live/{{ domain }}/fullchain.pem /etc/letsencrypt/live/{{ domain }}/privkey.pem > /etc/letsencrypt/live/{{ domain }}/master.pem:
  cmd.run:
    - creates:
      - /etc/letsencrypt/live/{{ domain }}/master.pem

haproxy_{{ domain }}_service_running:
  service.running:
    - name: haproxy

systemctl stop haproxy.service && letsencrypt renew --non-interactive --standalone --agree-tos && cat /etc/letsencrypt/live/{{ domain }}/fullchain.pem /etc/letsencrypt/live/{{ domain }}/privkey.pem > /etc/letsencrypt/live/{{ domain }}/master.pem && systemctl start haproxy.service:
  cron.present:
    - dayweek: 0
    - minute: {{ loop.index0 }}
    - hour: 4

{% endfor %}

/etc/haproxy/haproxy.cfg:
  file.managed:
    - source: salt://apps/haproxy/files/haproxy.cfg
    - template: jinja
    - defaults:
         glance_api_hosts: |
           {% for host in pillar['glance_configuration']['glance_members'] -%}
           server {{ host }} {{ pillar['glance_configuration']['hosts'][loop.index0] }}:9292 check inter 2000 rise 2 fall 5
           {% endfor %}
         glance_registry_hosts: |
           {% for host in pillar['glance_configuration']['glance_members'] -%}
           server {{ host }} {{ pillar['glance_configuration']['hosts'][loop.index0] }}:9191 check inter 2000 rise 2 fall 5
           {% endfor %}
         dashboard_hosts: |
           {% for host in pillar['horizon_configuration']['horizon_members'] -%}
           server {{ host }} {{ pillar['horizon_configuration']['hosts'][loop.index0] }}:80 check inter 2000 rise 2 fall 5
           {% endfor %}
         nova_spiceproxy_hosts: |
           {% for host in pillar['nova_configuration']['nova_members'] -%}
           server {{ host }} {{ pillar['nova_configuration']['hosts'][loop.index0] }}:6082 check inter 2000 rise 2 fall 5
           {% endfor %}
         swift_rgw_hosts: |
           {% for host in pillar['rgw_configuration']['rgw_members'] -%}
           server {{ host }} {{ pillar['rgw_configuration']['hosts'][loop.index0] }}:7480 check inter 2000 rise 2 fall 5
           {% endfor %}
         keystone_hosts: |
           {% for host in pillar['keystone_configuration']['keystone_members'] -%}
           server {{ host }} {{ pillar['keystone_configuration']['hosts'][loop.index0] }}:5000 check inter 2000 rise 2 fall 5
           {% endfor %}
         nova_compute_api_hosts: |
           {% for host in pillar['nova_configuration']['nova_members'] -%}
           server {{ host }} {{ pillar['nova_configuration']['hosts'][loop.index0] }}:8774 check inter 2000 rise 2 fall 5
           {% endfor %}
         nova_metadata_api_hosts: |
           {% for host in pillar['nova_configuration']['nova_members'] -%}
           server {{ host }} {{ pillar['nova_configuration']['hosts'][loop.index0] }}:8775 check inter 2000 rise 2 fall 5
           {% endfor %}
         nova_placement_api_hosts: |
           {% for host in pillar['nova_configuration']['nova_members'] -%}
           server {{ host }} {{ pillar['nova_configuration']['hosts'][loop.index0] }}:8778 check inter 2000 rise 2 fall 5
           {% endfor %}
         cinder_api_hosts: |
           {% for host in pillar['cinder_configuration']['cinder_members'] -%}
           server {{ host }} {{ pillar['cinder_configuration']['hosts'][loop.index0] }}:8776 check inter 2000 rise 2 fall 5
           {% endfor %}
         neutron_api_hosts: |
           {% for host in pillar['neutron_configuration']['neutron_members'] -%}
           server {{ host }} {{ pillar['neutron_configuration']['hosts'][loop.index0] }}:9696 check inter 2000 rise 2 fall 5
           {% endfor %}
         heat_api_hosts: |
           {% for host in pillar['heat_configuration']['heat_members'] -%}
           server {{ host }} {{ pillar['heat_configuration']['hosts'][loop.index0] }}:8004 check inter 2000 rise 2 fall 5
           {% endfor %}
         heat_api_cfn_hosts: |
           {% for host in pillar['heat_configuration']['heat_members'] -%}
           server {{ host }} {{ pillar['heat_configuration']['hosts'][loop.index0] }}:8000 check inter 2000 rise 2 fall 5
           {% endfor %}
         magnum_hosts: |
           {% for host in pillar['magnum_configuration']['magnum_members'] -%}
           server {{ host }} {{ pillar['magnum_configuration']['hosts'][loop.index0] }}:9511 check inter 2000 rise 2 fall 5
           {% endfor %}
         ceilometer_hosts: |
           {% for host in pillar['ceilometer_configuration']['ceilometer_members'] -%}
           server {{ host }} {{ pillar['ceilometer_configuration']['hosts'][loop.index0] }}:8041 check inter 2000 rise 2 fall 5
           {% endfor %}
         designate_hosts: |
           {% for host in pillar['designate_configuration']['designate_members'] -%}
           server {{ host }} {{ pillar['designate_configuration']['hosts'][loop.index0] }}:9001 check inter 2000 rise 2 fall 5
           {% endfor %}
         zun_hosts: |
           {% for host in pillar['zun_configuration']['zun_members'] -%}
           server {{ host }} {{ pillar['zun_configuration']['hosts'][loop.index0] }}:9517 check inter 2000 rise 2 fall 5
           {% endfor %}
         zun_comp_hosts: |
           {% for host in pillar['zun_configuration']['zun_members'] -%}
           server {{ host }} {{ pillar['zun_configuration']['hosts'][loop.index0] }}:6784 check inter 2000 rise 2 fall 5
           {% endfor %}
         murano_hosts: |
           {% for host in pillar['murano_configuration']['murano_members'] -%}
           server {{ host }} {{ pillar['murano_configuration']['hosts'][loop.index0] }}:8082 check inter 2000 rise 2 fall 5
           {% endfor %}
