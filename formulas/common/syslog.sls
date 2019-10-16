/etc/rsyslog.d/10-syslog.conf:
  file.managed:
    - source: salt://formulas/common/files/10-syslog.conf
    - template: jinja
    - defaults:
{% if salt['pillar.get']('syslog_url', False) != False %}
        logger: {{ pillar['syslog_url'] }}
{% else %}
        logger: 127.0.0.1:5514
{% endif %}                
{% if salt['pillar.get']('syslog_url', False) == False %}
  {% for host, addresses in salt['mine.get']('role:graylog', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
    {% for address in addresses %}
      {% if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
    - context:
        logger: {{ address }}:5514
      {% endif %}
    {% endfor %}
  {% endfor %}
{% endif %}

rsyslog:
  service.running:
    - watch:
      - /etc/rsyslog.d/10-syslog.conf
