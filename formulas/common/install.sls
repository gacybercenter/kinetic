## if the number of cache endpoints is nonzero, iterate through all cache endpoints and if returned IP is in management network,
## use it when constructing the proxy configuration
{% if (grains['type'] not in ['cache','salt','pxe'] and salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length != 0) %}
  {% for address in salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain') | dictsort() | random() | last () if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management'])%}

set_package_proxy:
  file.managed:
    {% if grains['os_family'] == 'Debian' %}
    - name: /etc/apt/apt.conf.d/02proxy
    - contents: |
        Acquire::http { Proxy "http://{{ address }}:3142"; };
    {% elif grains['os_family'] == 'RedHat' %}
    - name: /etc/yum.conf
    - contents: |
        [main]
        gpgcheck=1
        installonly_limit=3
        clean_requirements_on_remove=True
        best=True
        skip_if_unavailable=False
        proxy=http://{{ address }}:3142
    {% endif %}
    - onlyif:
      - fun: network.connect
        host: {{ address }}
        port: 3142
  {% endfor %}
{% endif %}

{% if salt['grains.get']('upgraded') != True %}
update_all:
  pkg.uptodate:
    - refresh: true
  {% if grains['os_family'] == 'Debian' %}
    - dist_upgrade: True
  {% endif %}

upgraded:
  grains.present:
    - value: True
    - require:
      - update_all
{% endif %}

common_remove:
  pkg.removed:
    - pkgs:
      - firewalld

common_install:
  pkg.installed:
    - pkgs:
      - python3-pip
    - reload_modules: True
