/etc/rsyslog.d/10-syslog.conf:
  file.managed:
    - source: salt://formulas/common/files/10-syslog.conf
    - template: jinja
    - defaults:
{% if pillar['syslog_url'] = false %}
          {% for host, addresses in salt['mine.get']('role:graylog', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
            {% for address in addresses %}
              {% if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
        logger: {{ address }}:5514
              {% endif %}
            {% endfor %}
          {% endfor %}
{% else %}
        logger: {{ pillar['syslog_url'] }}
{% endif %}

rsyslog:
  service.running:
    - watch:
      - /etc/rsyslog.d/10-syslog.conf
