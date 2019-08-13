include:
  - /formulas/haproxy/install
  - formulas/common/base

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

{% for domain in pillar['haproxy']['tls_domains'] %}

acme_{{ domain }}:
  acme.cert:
    - name: {{ domain }}
    - email: {{ pillar['haproxy']['tls_email'] }}
    - renew: 14

cat /etc/letsencrypt/live/{{ domain }}/fullchain.pem /etc/letsencrypt/live/{{ domain }}/privkey.pem > /etc/letsencrypt/live/{{ domain }}/master.pem:
  cmd.run

systemctl stop haproxy.service && letsencrypt renew --non-interactive --standalone --agree-tos && cat /etc/letsencrypt/live/{{ domain }}/fullchain.pem /etc/letsencrypt/live/{{ domain }}/privkey.pem > /etc/letsencrypt/live/{{ domain }}/master.pem && systemctl start haproxy.service:
  cron.present:
    - dayweek: 0
    - minute: {{ loop.index0 }}
    - hour: 4

{% endfor %}

/etc/haproxy/haproxy.cfg:
  file.managed:
    - source: salt://formulas/haproxy/files/haproxy.cfg
    - template: jinja
    - defaults:
         hostname: {{ grains['id'] }}
         syslog: {{ pillar['syslog_url'] }}
         public_ip_address: {{ grains['ipv4'][1] }}
         management_ip_address: {{ grains['ipv4'][0] }}
         dashboard_domain: {{ pillar['haproxy']['dashboard_domain'] }}
         console_domain:  {{ pillar['haproxy']['console_domain'] }}
         docs_domain:  {{ pillar['haproxy']['docs_domain'] }}
         keystone_hosts: |
           {%- for host, address in salt['mine.get']('type:keystone', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:5000 check inter 2000 rise 2 fall 5
           {%- endfor %}
         glance_api_hosts: |
           {%- for host, address in salt['mine.get']('type:glance', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:9292 check inter 2000 rise 2 fall 5
           {%- endfor %}
         glance_registry_hosts: |
           {%- for host, address in salt['mine.get']('type:glance', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:9191 check inter 2000 rise 2 fall 5
           {%- endfor %}
         nova_compute_api_hosts: |
           {%- for host, address in salt['mine.get']('type:nova', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:8774 check inter 2000 rise 2 fall 5
           {%- endfor %}
         nova_metadata_api_hosts: |
           {%- for host, address in salt['mine.get']('type:nova', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:8775 check inter 2000 rise 2 fall 5
           {%- endfor %}
         nova_placement_api_hosts: |
           {%- for host, address in salt['mine.get']('type:nova', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:8778 check inter 2000 rise 2 fall 5
           {%- endfor %}
         nova_spiceproxy_hosts: |
           {%- for host, address in salt['mine.get']('type:nova', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:6082 check inter 2000 rise 2 fall 5
           {%- endfor %}
         dashboard_hosts: |
           {%- for host, address in salt['mine.get']('type:horizon', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:80 check inter 2000 rise 2 fall 5
           {%- endfor %}
         docs_hosts: |
           {%- for host, address in salt['mine.get']('type:antora', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:80 check inter 2000 rise 2 fall 5
           {%- endfor %}
         neutron_api_hosts: |
           {%- for host, address in salt['mine.get']('type:neutron', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:9696 check inter 2000 rise 2 fall 5
           {%- endfor %}
         heat_api_hosts: |
           {%- for host, address in salt['mine.get']('type:heat', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:8004 check inter 2000 rise 2 fall 5
           {%- endfor %}
         heat_api_cfn_hosts: |
           {%- for host, address in salt['mine.get']('type:heat', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:8000 check inter 2000 rise 2 fall 5
           {%- endfor %}
         cinder_api_hosts: |
           {%- for host, address in salt['mine.get']('type:cinder', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:8776 check inter 2000 rise 2 fall 5
           {%- endfor %}
         designate_api_hosts: |
           {%- for host, address in salt['mine.get']('type:designate', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:9001 check inter 2000 rise 2 fall 5
           {%- endfor %}
         swift_hosts: |
           {%- for host, address in salt['mine.get']('type:swift', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:7480 check inter 2000 rise 2 fall 5
           {%- endfor %}
         zun_api_hosts: |
           {%- for host, address in salt['mine.get']('type:zun', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:9517 check inter 2000 rise 2 fall 5
           {%- endfor %}
         zun_wsproxy_hosts: |
           {%- for host, address in salt['mine.get']('type:zun', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
           server {{ host }} {{ address[0] }}:6784 check inter 2000 rise 2 fall 5
           {%- endfor %}

haproxy_cfg_watch:
  service.running:
    - name: haproxy
    - watch:
      - file: /etc/haproxy/haproxy.cfg
