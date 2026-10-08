# -*- coding: utf-8 -*-
"""
Identity lifecycle helpers.

# Implements: 800-171 3.5.6
Disable unused identifiers after inactivity by locking the OpenLDAP
entry (pwdAccountLockedTime). Keycloak LDAP federation is READ_ONLY, so
a Keycloak-only enabled=false does not persist across sync.
This is not sso_session_idle_timeout (that closed 3.13.9).
"""

import datetime
import logging
import re

log = logging.getLogger(__name__)

__virtualname__ = "kinetic_identity"

_LOCKED_VALUE = "000001010000Z"


def __virtual__():
    return __virtualname__


def _cfg(overrides=None):
    inactivity = dict(__salt__["pillar.get"]("ldap:inactivity", {}) or {})
    if overrides:
        inactivity.update({k: v for k, v in overrides.items() if v is not None})
    root_dn = __salt__["pillar.get"](
        "ldap:root_dn:dn", "dc=rsc,dc=gacyberrange,dc=org"
    )
    return {
        "inactive_days": int(inactivity.get("inactive_days", 90)),
        "grace_days": int(inactivity.get("grace_days", 7)),
        "dry_run": bool(inactivity.get("dry_run", True)),
        "users_base_dn": inactivity.get(
            "users_base_dn", f"ou=users,{root_dn}"
        ),
        "groups_base_dn": inactivity.get(
            "groups_base_dn", f"ou=groups,{root_dn}"
        ),
        "exclude_uids": [str(x) for x in inactivity.get("exclude_uids", [])],
        "exclude_dns": [str(x) for x in inactivity.get("exclude_dns", [])],
        "exclude_groups": [str(x) for x in inactivity.get("exclude_groups", [])],
        "exclude_uid_regex": inactivity.get("exclude_uid_regex") or "",
        "index": inactivity.get("index", "keycloak-logs-*"),
        "event_type_field": inactivity.get("event_type_field", "type.keyword"),
        "event_type_value": inactivity.get("event_type_value", "LOGIN"),
        "user_id_field": inactivity.get("user_id_field", "userId.keyword"),
        "username_field": inactivity.get(
            "username_field", "details.username.keyword"
        ),
        "timestamp_field": inactivity.get("timestamp_field", "time"),
        "opensearch_host": inactivity.get(
            "opensearch_host",
            "https://api.logger.services.gacyberrange.org:443",
        ),
        "allow_empty_login_index": bool(
            inactivity.get("allow_empty_login_index", False)
        ),
        "user_filter": inactivity.get("user_filter", "(objectClass=inetOrgPerson)"),
        "spec_name": inactivity.get("spec_name", "ldap_keycloak_connection"),
    }


def _parse_generalized_time(value):
    if not value:
        return None
    text = str(value).rstrip("Z").split(".", 1)[0]
    for length, fmt in ((14, "%Y%m%d%H%M%S"), (12, "%Y%m%d%H%M"), (8, "%Y%m%d")):
        if len(text) >= length:
            try:
                return datetime.datetime.strptime(text[:length], fmt)
            except ValueError:
                continue
    return None


def _first(attrs, key):
    values = (attrs or {}).get(key) or []
    return values[0] if values else ""


def _recent_logins(cfg):
    body = {
        "size": 0,
        "track_total_hits": True,
        "query": {
            "bool": {
                "must": [
                    {"term": {cfg["event_type_field"]: cfg["event_type_value"]}},
                    {
                        "range": {
                            cfg["timestamp_field"]: {
                                "gte": f"now-{cfg['inactive_days']}d"
                            }
                        }
                    },
                ]
            }
        },
        "aggs": {
            "by_username": {
                "terms": {"field": cfg["username_field"], "size": 10000}
            },
            "by_userid": {
                "terms": {"field": cfg["user_id_field"], "size": 10000}
            },
        },
    }
    result = __salt__["kinetic-os.search"](
        index=cfg["index"],
        body=body,
        host=cfg["opensearch_host"],
    )
    if not result.get("success"):
        return {
            "success": False,
            "usernames": set(),
            "userids": set(),
            "hits": 0,
            "message": result.get("message"),
        }
    data = result.get("data") or {}
    hits = ((data.get("hits") or {}).get("total")) or 0
    if isinstance(hits, dict):
        hits = hits.get("value", 0)
    aggs = data.get("aggregations") or {}
    usernames = {
        bucket["key"]
        for bucket in (aggs.get("by_username") or {}).get("buckets", [])
        if bucket.get("key")
    }
    userids = {
        bucket["key"]
        for bucket in (aggs.get("by_userid") or {}).get("buckets", [])
        if bucket.get("key")
    }
    return {
        "success": True,
        "usernames": usernames,
        "userids": userids,
        "hits": hits,
        "message": f"Found {hits} {cfg['event_type_value']} events",
    }


def _exclude_group_members(cfg):
    members = set()
    if not cfg["exclude_groups"]:
        return members
    groups_base = cfg["groups_base_dn"]
    for group in cfg["exclude_groups"]:
        if "=" in group:
            group_dn = group
        else:
            group_dn = f"cn={group},{groups_base}"
        result = __salt__["ldap_utils.search_entries"](
            cfg["spec_name"],
            group_dn,
            filterstr="(objectClass=*)",
            attributes=["member", "uniqueMember"],
            scope=0,
        )
        if not result.get("success"):
            log.warning("Could not read exclude group %s: %s", group_dn, result.get("error"))
            continue
        for entry in result.get("entries") or []:
            attrs = entry.get("attributes") or {}
            for attr in ("member", "uniqueMember"):
                members.update(attrs.get(attr) or [])
    return members


def _should_skip(entry, cfg, exclude_members):
    dn = entry["dn"]
    attrs = entry.get("attributes") or {}
    uid = _first(attrs, "uid")
    reasons = []
    if uid and uid in cfg["exclude_uids"]:
        reasons.append("exclude_uid")
    if dn in cfg["exclude_dns"]:
        reasons.append("exclude_dn")
    if dn in exclude_members:
        reasons.append("exclude_group")
    if cfg["exclude_uid_regex"] and uid and re.search(cfg["exclude_uid_regex"], uid):
        reasons.append("exclude_uid_regex")
    if _first(attrs, "pwdAccountLockedTime"):
        reasons.append("already_locked")
    return reasons


def _ensure_ldap_spec(cfg):
    """Recreate the StartTLS bind used by ldapadmin/prov.sls if the cache is cold."""
    existing = __salt__["ldap_utils.get_connect_spec"](cfg["spec_name"])
    if existing.get("success"):
        return {"success": True, "message": "LDAP connect spec already cached"}
    ldap_pillar = __salt__["pillar.get"]("ldap", {}) or {}
    admin = ldap_pillar.get("admin-user", {}) or {}
    cert = ldap_pillar.get("cert", {}) or {}
    domain = (
        ((ldap_pillar.get("values") or {}).get("global") or {}).get("ldapDomain")
        or (ldap_pillar.get("root_dn") or {}).get("dn")
    )
    ca_path = "/tmp/ca.pem"
    ca = cert.get("ca")
    if ca:
        with open(ca_path, "w") as ca_fh:
            ca_fh.write(ca if isinstance(ca, str) else str(ca))
    connection_dict = {
        "url": "ldap://" + cert.get("commonname", ""),
        "bind": {
            "dn": "cn={0},{1}".format(admin.get("name"), domain),
            "password": admin.get("password"),
            "method": "simple",
        },
        "tls": {"cacertfile": ca_path, "starttls": True},
    }
    created = __salt__["ldap_utils.create_connect_spec"](
        cfg["spec_name"], connection_dict
    )
    if not created.get("success"):
        return {
            "success": False,
            "message": created.get("error") or "Failed to create LDAP connect spec",
        }
    return {"success": True, "message": "LDAP connect spec created"}


def disable_inactive(
    dry_run=None,
    inactive_days=None,
    grace_days=None,
    spec_name=None,
):
    """
    Find users with no successful LOGIN for N days and lock them in OpenLDAP.

    New accounts without LOGIN events are skipped for grace_days (based on
    createTimestamp). Service accounts and instructors must be listed in
    pillar exclude_* — this function does not guess them.

    CLI Example:

        salt-call kinetic_identity.disable_inactive dry_run=True
    """
    cfg = _cfg(
        {
            "dry_run": dry_run,
            "inactive_days": inactive_days,
            "grace_days": grace_days,
            "spec_name": spec_name,
        }
    )
    spec = _ensure_ldap_spec(cfg)
    if not spec.get("success"):
        return {
            "success": False,
            "dry_run": cfg["dry_run"],
            "would_disable": [],
            "disabled": [],
            "skipped": [],
            "message": spec.get("message"),
        }
    logins = _recent_logins(cfg)
    if not logins["success"]:
        return {
            "success": False,
            "dry_run": cfg["dry_run"],
            "would_disable": [],
            "disabled": [],
            "skipped": [],
            "message": logins["message"],
        }
    if logins["hits"] == 0 and not cfg["allow_empty_login_index"]:
        return {
            "success": False,
            "dry_run": cfg["dry_run"],
            "would_disable": [],
            "disabled": [],
            "skipped": [],
            "message": (
                f"No {cfg['event_type_value']} events in {cfg['index']} for "
                f"{cfg['inactive_days']}d; refusing to disable anyone. "
                "Set ldap:inactivity:allow_empty_login_index only for a "
                "dedicated test."
            ),
        }

    users = __salt__["ldap_utils.search_entries"](
        cfg["spec_name"],
        cfg["users_base_dn"],
        filterstr=cfg["user_filter"],
        attributes=[
            "uid",
            "cn",
            "entryUUID",
            "createTimestamp",
            "pwdAccountLockedTime",
        ],
    )
    if not users.get("success"):
        return {
            "success": False,
            "dry_run": cfg["dry_run"],
            "would_disable": [],
            "disabled": [],
            "skipped": [],
            "message": users.get("error"),
        }

    exclude_members = _exclude_group_members(cfg)
    now = datetime.datetime.utcnow()
    grace_cutoff = now - datetime.timedelta(days=cfg["grace_days"])
    skipped = []
    candidates = []
    for entry in users.get("entries") or []:
        attrs = entry.get("attributes") or {}
        uid = _first(attrs, "uid")
        uuid = _first(attrs, "entryUUID")
        skip_reasons = _should_skip(entry, cfg, exclude_members)
        if skip_reasons:
            skipped.append({"dn": entry["dn"], "uid": uid, "reason": ",".join(skip_reasons)})
            continue
        if uid in logins["usernames"] or uuid in logins["userids"]:
            skipped.append({"dn": entry["dn"], "uid": uid, "reason": "recent_login"})
            continue
        created = _parse_generalized_time(_first(attrs, "createTimestamp"))
        if created and created > grace_cutoff:
            skipped.append({"dn": entry["dn"], "uid": uid, "reason": "grace_period"})
            continue
        candidates.append(
            {
                "dn": entry["dn"],
                "uid": uid,
                "created": created.isoformat() if created else "",
            }
        )

    disabled = []
    errors = []
    for candidate in candidates:
        line = (
            f"{'[dry-run] would disable' if cfg['dry_run'] else 'disable'} "
            f"uid={candidate['uid']} dn={candidate['dn']} "
            f"created={candidate['created'] or 'unknown'}"
        )
        log.info(line)
        if cfg["dry_run"]:
            continue
        result = __salt__["ldap_utils.set_account_locked"](
            cfg["spec_name"], candidate["dn"], True
        )
        if result.get("success"):
            disabled.append(candidate)
        else:
            errors.append(
                {"dn": candidate["dn"], "uid": candidate["uid"], "error": result.get("message")}
            )

    success = not errors
    message = (
        f"{'Dry-run: would disable' if cfg['dry_run'] else 'Disabled'} "
        f"{len(candidates)} identifier(s); skipped {len(skipped)}. "
        f"{logins['message']}."
    )
    if errors:
        message += f" Errors: {len(errors)}"
    return {
        "success": success,
        "dry_run": cfg["dry_run"],
        "inactive_days": cfg["inactive_days"],
        "grace_days": cfg["grace_days"],
        "would_disable": candidates if cfg["dry_run"] else [],
        "disabled": disabled,
        "skipped": skipped,
        "errors": errors,
        "message": message,
    }
