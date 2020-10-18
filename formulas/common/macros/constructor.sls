

### This macro is used to create openstack endpoint URLs
### project means the openstack project, e.g. keystone
### service means the service as defined in the service catalog, e.g. cinderv2, etc.
### endpoint means the endpoint type, e.g. public, internal, or admin
{% macro endpoint_url_constructor(project, service, endpoint) -%}

{%- set service_configuration = salt['pillar.get']('openstack_services:'+project+':configuration:services:'+service+':endpoints:'+endpoint, {"protocol":"TBD","port":"TBD","path":"TBD"}) -%}
{{ service_configuration['protocol'] }}{{ pillar['endpoints'][endpoint] }}{{ service_configuration['port'] }}{{ service_configuration['path'] }}

{%- endmacro -%}

### This macro is used to created openstack base endpoint URLs.
### Basically the same as endpoint_url_constructor, except it has no path suffix
{% macro base_endpoint_url_constructor(project, service, endpoint) -%}

{%- set service_configuration = salt['pillar.get']('openstack_services:'+project+':configuration:services:'+service+':endpoints:'+endpoint, {"protocol":"TBD","port":"TBD","path":"TBD"}) -%}
{{ service_configuration['protocol'] }}{{ pillar['endpoints'][endpoint] }}{{ service_configuration['port'] }}

{%- endmacro -%}

### This macro creates rmq url strings
{% macro rabbitmq_url_constructor() -%}

rabbit://
  {%- for host, addresses in salt['mine.get']('role:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
    {%- for address in addresses  if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
  openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address }}
    {%- endfor -%}
    {% if loop.index < loop.length %},{% endif %}
  {%- endfor %}

{%- endmacro -%}

### This macro creates memcached cluster strings
{% macro memcached_url_constructor() -%}

{%- for host, addresses in salt['mine.get']('role:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
  {%- for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
    {%- if grains['role'] == 'horizon' -%}
      {% set address = "\"+"'"+address+":11211'" %}
    {%- else -%}
      {% set address = address+":11211" %}
    {%- endif -%}
{{ address }}
  {%- endfor -%}
  {% if loop.index < loop.length %},{% endif %}
{%- endfor %}

{%- endmacro -%}

### This macro creates sql cluster connection strings
{% macro mysql_url_constructor(user, database) -%}

mysql+pymysql://{{ user }}:{{ pillar[user][user+'_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/{{ database }}

{%- endmacro -%}

{%- macro ovn_sb_connection_constructor() -%}

{%- for host, addresses in salt['mine.get']('role:ovsdb', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
  {%- for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
tcp:{{ address }}:6642
  {%- endfor -%}
  {% if loop.index < loop.length %},{% endif %}
{%- endfor %}

{%- endmacro -%}

### This macro creates etcd cluster strings
{%- macro etcd_connection_constructor() -%}

etcd://
{%- for host, addresses in salt['mine.get']('role:etcd', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
  {%- for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
    {{ address }}:2379
  {%- endfor -%}
  {% if loop.index < loop.length %},{% endif %}
{%- endfor %}

{%- endmacro -%}


## This macro returns an IP for a spawnzero for a given type on a given network
{%- macro spawnzero_ip_constructor(type, network) -%}

{% for host, addresses in salt['mine.get']('G@role:'+type+' and G@spawning:0', 'network.ip_addrs', tgt_type='compound') | dictsort() -%}
  {%- for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets'][network]) -%}
{{ address }}
  {%- endfor -%}
{%- endfor %}

{%- endmacro -%}

## This macro returns an haproxy listenter entry
## it has horrible indentation because of the nature of yaml_encode - it treats spaces as literals if the space
## is contained inside of a statement (e.g. before an endfor on a newline)
{%- macro haproxy_listener_constructor(role, port) -%}

{%- if port is not match(':(.*)') -%}
  {% set port = [":",port]| join %}
{%- endif -%}

{%- if role == 'mysql' -%}
  {% for host, addresses in salt['mine.get']('G@type:mysql and G@spawning:0', 'network.ip_addrs', tgt_type='compound') | dictsort() -%}
    {%- for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
server {{ host }} {{ address }}{{ port }} check inter 2000 rise 2 fall 5
{% endfor -%}
  {%- endfor -%}
  {% for host, addresses in salt['mine.get']('G@type:mysql and not G@spawning:0', 'network.ip_addrs', tgt_type='compound') | dictsort() -%}
    {%- for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
server {{ host }} {{ address }}{{ port }} check inter 2000 rise 2 fall 5 backup
{% endfor -%}
  {%- endfor -%}
{%- else -%}
  {% for host, addresses in salt['mine.get']('role:'+role, 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
    {%- for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
server {{ host }} {{ address }}{{ port }} check inter 2000 rise 2 fall 5
{% endfor -%}
  {%- endfor -%}
{%- endif -%}

{%- endmacro -%}
