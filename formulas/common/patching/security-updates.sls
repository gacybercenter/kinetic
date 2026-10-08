# Implements: 800-171 3.14.1
# Weekly security-update cadence. dry_run defaults true so G2 can
# prove the job exists without applying packages in production.
# Pair with nist-gcr SOP/[DRAFT] Flaw Identification and Salt Patch Procedure.markdown
# and kinetic-pillar environment/patching.sls.

{% set patch = salt['pillar.get']('patching', {}) %}
{% if patch.get('enabled', False) %}

{% if not patch.get('dry_run', True) %}
security_updates:
  pkg.uptodate:
    - refresh: True
{% else %}
security_updates_dry_run:
  test.nop:
    - name: "3.14.1 dry_run: set patching:dry_run false after G2 and a maintenance window"
{% endif %}

security_updates_schedule:
  schedule.present:
    - function: state.sls
    - job_args:
      - formulas.common.patching.security-updates
    - days: {{ patch.get('schedule_days', 7) }}
    - splay: 3600

{% endif %}
