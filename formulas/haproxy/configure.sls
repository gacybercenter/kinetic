include:
  - /formulas/haproxy/install
  - formulas/common/base
  - formulas/common/networking

{% for domain in pillar['haproxy']['tls_domains'] %}

haproxy_{{ domain }}_service_dead:
  service.dead:
    - name: haproxy
    - prereq:
      - letsencrypt certonly -d {{ domain }} --agree-tos --email {{ pillar['haproxy']['tls_email'] }}

letsencrypt certonly -d {{ domain }} --agree-tos --email {{ pillar['haproxy']['tls_email'] }}:
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

{% endfor %}
