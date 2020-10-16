{% macro endpoint_url_constructor(service, api_version, endpoint) %}

{{ pillar['openstack_services'][service] }}
{% endmacro %}


#+{{ pillar['openstack_services'][service]['configuration']['endpoints']['api_version'][api_version][endpoint] }}+{{ pillar['openstack_services'][service]['configuration']['endpoints']['api_version'][api_version][endpoint]['port'] }}
#['configuration']['endpoints']['api_version'][api_version][endpoint]['protocol']
