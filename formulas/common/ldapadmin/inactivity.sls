# Implements: 800-171 3.5.6
# Disable unused identifiers after N days with no successful LOGIN.
# Locks the OpenLDAP entry (pwdAccountLockedTime). Does not use
# sso_session_idle_timeout (3.13.9). Does not stop Fluent Bit.
#
# N, grace, excludes, and the OpenSearch index come from kinetic-pillar.
# Default N=90. dry_run defaults true so G2 can log a stale test user
# without locking instructors.

include:
  - /formulas/common/ldapadmin/prov

{% set inactivity = pillar.get('ldap', {}).get('inactivity', {}) %}
{% if inactivity.get('enabled') %}
{% set root_dn = pillar.get('ldap', {}).get('root_dn', {}).get('dn', 'dc=rsc,dc=gacyberrange,dc=org') %}
{% set dry_run = inactivity.get('dry_run', True) %}
{% set inactive_days = inactivity.get('inactive_days', 90) %}

ldap_inactivity_schedule:
  schedule.present:
    - function: kinetic_identity.disable_inactive
    - hours: {{ inactivity.get('schedule_hours', 24) }}
    - kwargs:
        dry_run: {{ dry_run }}
        inactive_days: {{ inactive_days }}
    - require:
      - ldap: ensure_ldap_connect_spec

{% set cron = inactivity.get('cronjob', {}) %}
{% if cron.get('enabled') %}
{% set cron_image = cron.get('image') %}
{% if not cron_image %}
ldap_inactivity_cronjob_image_required:
  test.fail_without_changes:
    - name: ldap:inactivity:cronjob:image must be set in kinetic-pillar when the CronJob is enabled
{% else %}
{% set cron_ns = cron.get('namespace', pillar.get('ldap', {}).get('namespace', 'ldap')) %}
{% set admin_secret = pillar.get('ldap', {}).get('values', {}).get('global', {}).get('existingSecret', 'openldap-admin') %}
{% set os_secret = cron.get('opensearch_secret', 'fluentbit-creds') %}
{% set os_user_key = cron.get('opensearch_user_key', 'OPENSEARCH_USERNAME') %}
{% set os_pass_key = cron.get('opensearch_password_key', 'OPENSEARCH_PASSWORD') %}
{% set ldap_domain = pillar.get('ldap', {}).get('values', {}).get('global', {}).get('ldapDomain', root_dn) %}

ldap_inactivity_script:
  k8s.configmap_present:
    - name: ldap-inactivity-script
    - configmap_name: ldap-inactivity-script
    - namespace: {{ cron_ns }}
    - data:
        disable_inactive.py: {{ salt['cp.get_file_str']('salt://formulas/common/ldapadmin/files/disable_inactive.py') | tojson }}

ldap_inactivity_cronjob:
  k8s.cronjob_present:
    - name: ldap-disable-inactive
    - namespace: {{ cron_ns }}
    - schedule: {{ cron.get('schedule', '15 6 * * *') | yaml_dquote }}
    - image: {{ cron_image }}
    - command:
      - python3
    - args:
      - /scripts/disable_inactive.py
    - restart_policy: OnFailure
    - env:
      - name: DRY_RUN
        value: "{{ 'true' if dry_run else 'false' }}"
      - name: INACTIVE_DAYS
        value: "{{ inactive_days }}"
      - name: GRACE_DAYS
        value: "{{ inactivity.get('grace_days', 7) }}"
      - name: USERS_BASE_DN
        value: {{ inactivity.get('users_base_dn', 'ou=users,' ~ root_dn) | yaml_dquote }}
      - name: EXCLUDE_UIDS
        value: {{ inactivity.get('exclude_uids', []) | join(',') | yaml_dquote }}
      - name: EXCLUDE_DNS
        value: {{ inactivity.get('exclude_dns', []) | join(',') | yaml_dquote }}
      - name: EXCLUDE_UID_REGEX
        value: {{ inactivity.get('exclude_uid_regex', '') | yaml_dquote }}
      - name: OPENSEARCH_INDEX
        value: {{ inactivity.get('index', 'keycloak-logs-*') | yaml_dquote }}
      - name: EVENT_TYPE_FIELD
        value: {{ inactivity.get('event_type_field', 'type.keyword') | yaml_dquote }}
      - name: EVENT_TYPE_VALUE
        value: {{ inactivity.get('event_type_value', 'LOGIN') | yaml_dquote }}
      - name: USER_ID_FIELD
        value: {{ inactivity.get('user_id_field', 'userId.keyword') | yaml_dquote }}
      - name: USERNAME_FIELD
        value: {{ inactivity.get('username_field', 'details.username.keyword') | yaml_dquote }}
      - name: TIMESTAMP_FIELD
        value: {{ inactivity.get('timestamp_field', 'time') | yaml_dquote }}
      - name: OPENSEARCH_HOST
        value: {{ inactivity.get('opensearch_host', 'https://api.logger.services.gacyberrange.org:443') | yaml_dquote }}
      - name: LDAP_URL
        value: {{ ("ldap://" ~ pillar['ldap']['cert']['commonname']) | yaml_dquote }}
      - name: LDAP_BIND_DN
        value: {{ ("cn=" ~ pillar['ldap']['admin-user']['name'] ~ "," ~ ldap_domain) | yaml_dquote }}
      - name: LDAP_CA_FILE
        value: /tls/ca.pem
      - name: LDAP_BIND_PASSWORD
        valueFrom:
          secretKeyRef:
            name: {{ admin_secret }}
            key: LDAP_ADMIN_PASSWORD
      - name: OPENSEARCH_USERNAME
        valueFrom:
          secretKeyRef:
            name: {{ os_secret }}
            key: {{ os_user_key }}
      - name: OPENSEARCH_PASSWORD
        valueFrom:
          secretKeyRef:
            name: {{ os_secret }}
            key: {{ os_pass_key }}
    - volumes:
      - name: script
        configMap:
          name: ldap-inactivity-script
          defaultMode: 0555
      - name: ldap-ca
        configMap:
          name: {{ cron.get('ca_configmap', 'ldap-inactivity-ca') }}
    - volume_mounts:
      - name: script
        mountPath: /scripts
      - name: ldap-ca
        mountPath: /tls
        readOnly: true
    - require:
      - k8s: ldap_inactivity_script
      - k8s: ldap_inactivity_ca

ldap_inactivity_ca:
  k8s.configmap_present:
    - name: {{ cron.get('ca_configmap', 'ldap-inactivity-ca') }}
    - configmap_name: {{ cron.get('ca_configmap', 'ldap-inactivity-ca') }}
    - namespace: {{ cron_ns }}
    - data:
        ca.pem: {{ pillar['ldap']['cert']['ca'] | tojson }}
{% endif %}
{% endif %}
{% endif %}
