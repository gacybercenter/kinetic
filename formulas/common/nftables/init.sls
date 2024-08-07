{% set type = pillar['type'] %}

{% if type != 'pxe' or type != 'salt' %}
include:
  .nftables
{% endif %}