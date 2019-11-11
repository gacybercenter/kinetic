include:
  - /formulas/haproxy/install
  - formulas/common/base

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

{% if grains['os_family'] == "RedHat" %}
haproxy_connect_any:
  selinux.boolean:
    - value: True
    - persist: True
{% endif %}

{% for domain in pillar['haproxy']['tls_domains'] %}

acme_{{ domain }}:
  acme.cert:
    - name: {{ domain }}
    - email: {{ pillar['haproxy']['tls_email'] }}
    - renew: 14

cat /etc/letsencrypt/live/{{ domain }}/fullchain.pem /etc/letsencrypt/live/{{ domain }}/privkey.pem > /etc/letsencrypt/live/{{ domain }}/master.pem:
  cmd.run:
    - onchanges:
      - acme: acme_{{ domain }}

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
{% if salt['pillar.get']('syslog_url', False) == False %}
  {% for host, addresses in salt['mine.get']('role:graylog', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
    {% for address in addresses %}
      {% if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
    - context:
        syslog: {{ address }}:5514
      {% endif %}
    {% endfor %}
  {% endfor %}
{% endif %}
{% if grains['os_family'] == "RedHat" %}
        seamless_reload: ""
{% endif %}
    - defaults:
{% if salt['pillar.get']('syslog_url', False) != False %}
        syslog: {{ pillar['syslog_url'] }}
{% else %}
        syslog: 127.0.0.1:5514
{% endif %}
        seamless_reload: stats socket /var/run/haproxy.sock mode 600 expose-fd listeners level user
        hostname: {{ grains['id'] }}
        management_ip_address: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        dashboard_domain: {{ pillar['haproxy']['dashboard_domain'] }}
        console_domain:  {{ pillar['haproxy']['console_domain'] }}
        docs_domain:  {{ pillar['haproxy']['docs_domain'] }}
        keystone_hosts: |
          {%- for host, addresses in salt['mine.get']('type:keystone', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}{{ pillar['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }} check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        glance_api_hosts: |
          {%- for host, addresses in salt['mine.get']('type:glance', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}{{ pillar['openstack_services']['glance']['configuration']['public_endpoint']['port'] }} check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        nova_compute_api_hosts: |
          {%- for host, addresses in salt['mine.get']('type:nova', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}{{ pillar['openstack_services']['nova']['configuration']['public_endpoint']['port'] }} check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        nova_metadata_api_hosts: |
          {%- for host, addresses in salt['mine.get']('type:nova', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}:8775 check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        placement_api_hosts: |
          {%- for host, addresses in salt['mine.get']('type:placement', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}:8778 check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        nova_spiceproxy_hosts: |
          {%- for host, addresses in salt['mine.get']('type:nova', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}:6082 check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        dashboard_hosts: |
          {%- for host, addresses in salt['mine.get']('type:horizon', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}:80 check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        docs_hosts: |
          {%- for host, addresses in salt['mine.get']('type:antora', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}:80 check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        neutron_api_hosts: |
          {%- for host, addresses in salt['mine.get']('type:neutron', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}{{ pillar['openstack_services']['neutron']['configuration']['public_endpoint']['port'] }} check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        heat_api_hosts: |
          {%- for host, addresses in salt['mine.get']('type:heat', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}{{ pillar['openstack_services']['heat']['configuration']['public_endpoint']['port'] }} check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        heat_api_cfn_hosts: |
          {%- for host, addresses in salt['mine.get']('type:heat', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}{{ pillar['openstack_services']['heat']['configuration']['public_endpoint_cfn']['port'] }} check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        cinder_api_hosts: |
          {%- for host, addresses in salt['mine.get']('type:cinder', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}{{ pillar['openstack_services']['cinder']['configuration']['public_endpoint']['port'] }} check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        designate_api_hosts: |
          {%- for host, addresses in salt['mine.get']('type:designate', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}{{ pillar['openstack_services']['designate']['configuration']['public_endpoint']['port'] }} check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        swift_hosts: |
          {%- for host, addresses in salt['mine.get']('type:swift', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}{{ pillar['openstack_services']['swift']['configuration']['public_endpoint']['port'] }} check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        zun_api_hosts: |
          {%- for host, addresses in salt['mine.get']('type:zun', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}{{ pillar['openstack_services']['zun']['configuration']['public_endpoint']['port'] }} check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
        zun_wsproxy_hosts: |
          {%- for host, addresses in salt['mine.get']('type:zun', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
          server {{ host }} {{ address }}:6784 check inter 2000 rise 2 fall 5
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}

haproxy_service_watch:
  service.running:
    - name: haproxy
    - reload: true
    - watch:
      - file: /etc/haproxy/haproxy.cfg
