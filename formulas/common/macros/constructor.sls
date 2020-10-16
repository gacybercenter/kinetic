{% macro endpoint_url_constructor(project, service, endpoint) -%}

{%- set service_configuration = pillar['openstack_services'][project]['configuration']['services'][service]['endpoints'][endpoint] -%}
{{ service_configuration['protocol'] }}{{ pillar['endpoints'][endpoint] }}{{ service_configuration['port'] }}{{ service_configuration['path'] }}

{%- endmacro -%}

{% macro base_endpoint_url_constructor(project, service, endpoint) -%}

{%- set service_configuration = pillar['openstack_services'][project]['configuration']['services'][service]['endpoints'][endpoint] -%}
{{ service_configuration['protocol'] }}{{ pillar['endpoints'][endpoint] }}{{ service_configuration['port'] }}

{%- endmacro -%}

{% macro rmq_url_constructor() -%}

rabbit://
  {%- for host, addresses in salt['mine.get']('role:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
    {%- for address in addresses -%}
      {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
  openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address }}
      {%- endif -%}
    {%- endfor -%}
    {% if loop.index < loop.length %},{% endif %}
  {%- endfor %}

{%- endmacro -%}
