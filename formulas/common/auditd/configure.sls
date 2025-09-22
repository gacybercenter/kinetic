include:
  - /formulas/common/auditd/install

auditd_service:
  service.running:
    - name: auditd
    - enable: True
    - require:
      - pkg: auditd_package

# Add audit rules for login attempts, file access, and configuration changes
auditd_rules_file:
  file.managed:
    - name: /etc/audit/rules.d/custom.rules
    - source: salt://formulas/common/auditd/files/custom.rules
    - mode: 640
    - user: root
    - group: root
    - watch_in:
      - service: auditd_service