{% set hostname = data['path'].split('/')[6] %}
{% set type = hostname.split('-')[0] %}

notify master of assignment:
  runner.event.send:
    - args:
      - tag: /new/hostname/assigned/{{ hostname }}
      - data:
          hostname: {{ hostname }}
          type: {{ type }}

notify master of hostname:
  runner.event.send:
    - args:
      - tag: /new/hostname/is/{{ hostname }}
      - data:
          hostname: {{ hostname }}
          type: {{ type }}
