/etc/rsyslog.d/10-syslog.conf:
  file.managed:
    - source: salt://formulas/common/files/10-syslog.conf
    - template: jinja
    - defaults:
        centralized_logger: {{ pillar['syslog_url'] }}

rsyslog:
  service.running:
    - watch:
      - /etc/rsyslog.d/10-syslog.conf
