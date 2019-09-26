{% set hostname = data['path'].split('/')[6] %}
{% set type = hostname.split('-')[0] %}

publish pending id:
  runner.event.send:
    - args:
      - tag: /newhost/{{ hostname }}
      - data:
          hostname: {{ hostname }}
          type: {{ type }}
