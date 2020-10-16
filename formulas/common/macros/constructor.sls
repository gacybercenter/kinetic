{% macro endpoint_url_constructor(project, service, endpoint) -%}

{%- set service_configuration = pillar['openstack_services'][project]['configuration']['services'][service]['endpoints'][endpoint] -%}
{{ service_configuration['protocol'] }}{{ pillar['endpoints'][endpoint] }}{{ service_configuration['port'] }}{{ service_configuration['path'] }}

{%- endmacro -%}

{% macro base_endpoint_url_constructor(project, service, endpoint) -%}

{%- set service_configuration = pillar['openstack_services'][project]['configuration']['services'][service]['endpoints'][endpoint] -%}
{{ service_configuration['protocol'] }}{{ pillar['endpoints'][endpoint] }}{{ service_configuration['port'] }}

{%- endmacro -%}
