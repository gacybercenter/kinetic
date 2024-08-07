{% set type = grains['type'] %}

{% if type != 'pxe' or type != 'salt' %}
include:
  .nftables
{% endif %}