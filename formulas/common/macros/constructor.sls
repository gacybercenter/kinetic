{% macro endpoint_url_constructor(service, api_version, endpoint) -%}
{{ pillar['openstack_services'][service]['configuration']['endpoints']['api_version'][api_version][endpoint]['protocol'] }}{{ pillar['endpoints'][endpoint] }}{{ pillar['openstack_services'][service]['configuration']['endpoints']['api_version'][api_version][endpoint]['port'] }}{{ pillar['openstack_services'][service]['configuration']['endpoints']['api_version'][api_version][endpoint]['path'] }}
{%- endmacro -%}
