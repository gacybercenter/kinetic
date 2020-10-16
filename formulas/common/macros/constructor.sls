{% macro endpoint_url_constructor(service, api_version, endpoint) -%}
{% set service_configuration = pillar['openstack_services'][service]['configuration']['endpoints']['api_version'][api_version][endpoint] %}
{{ service_configuration['protocol'] }}{{ service_configuration['port'] }}{{ service_configuration['path'] }}
{%- endmacro -%}
