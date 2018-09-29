{% for directive in pillar.get('master-config', {}).items() %}
/etc/salt/master.d/{{ directive}}.conf:
  file.managed:
    - contents_pillar: master-config:{{ directive }}
{% endfor %}
