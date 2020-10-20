### This macro is used to construct needs-check routines
### for use in the orchestrator
### This loop will block until confirmation is received that all networking
### deps have been met.  The logic is very similar to the initial dep check loop
### adding an additional one here will ensure that the deps needed for the
### next phase of the orch have been met, rather than just the bits needed to
### start

{%- macro needs_check_one(type, phase) -%}

{% if salt['pillar.get']('hosts:'+type+':needs:'+phase, {}) != {} %}
{{ type }}_{{ phase }}_phase_check_loop::
  salt.runner:
    - name: needs.check_one
    - kwarg:
        needs: {{ salt['pillar.get']('hosts:'+type+':needs:'+phase, {}) }}
        type: {{ type }}
    - retry:
        interval: 30
        attempts: 240
        splay: 10
    - require_in:
      - apply_{{ phase }}_{{ type }}
{% endif %}

{%- endmacro -%}
