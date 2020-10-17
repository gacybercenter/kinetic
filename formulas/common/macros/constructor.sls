

### This macro is used to create openstack endpoint URLs
### project means the openstack project, e.g. keystone
### service means the service as defined in the service catalog, e.g. cinderv2, etc.
### endpoint means the endpoint type, e.g. public, internal, or admin
{% macro endpoint_url_constructor(project, service, endpoint) -%}

{%- set service_configuration = pillar['openstack_services'][project]['configuration']['services'][service]['endpoints'][endpoint] -%}
{{ service_configuration['protocol'] }}{{ pillar['endpoints'][endpoint] }}{{ service_configuration['port'] }}{{ service_configuration['path'] }}

{%- endmacro -%}

### This macro is used to created openstack base endpoint URLs.
### Basically the same as endpoint_url_constructor, except it has no path suffix
{% macro base_endpoint_url_constructor(project, service, endpoint) -%}

{%- set service_configuration = pillar['openstack_services'][project]['configuration']['services'][service]['endpoints'][endpoint] -%}
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
{{ address }}:11211
  {%- endfor -%}
  {% if loop.index < loop.length %},{% endif %}
{%- endfor %}

{%- endmacro -%}

### This macro creates sql cluster connection strings
{% macro mysql_url_constructor(user, database) -%}

mysql+pymysql://{{ user }}:{{ pillar[user][user+'_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/{{ database }}

{%- endmacro -%}
