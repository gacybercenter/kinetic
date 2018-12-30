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
         hostname: {{ grains['id'] }}
         syslog: {{ pillar['syslog_url'] }}
         public_ip_address: {{ grains['ipv4'][1] }}
         certificates: |
{% for domain in pillar['haproxy']['tls_domains'] -%}
           crt /etc/letsencrypt/live/{{ domain }}/master.pem
{% endfor %}
         glance_api_hosts: |
           server glance 10.10.123.123:9292 check inter 2000 rise 2 fall 5
         dashboard_hosts: |
           server horizon 10.10.123.123:80 check inter 2000 rise 2 fall 5
         nova_spiceproxy_hosts: |
           server nova 10.10.123.123:6082 check inter 2000 rise 2 fall 5
