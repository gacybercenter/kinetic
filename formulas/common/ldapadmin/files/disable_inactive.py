#!/usr/bin/env python3
"""Disable unused LDAP identifiers after inactivity.

# Implements: 800-171 3.5.6

Standalone CronJob entrypoint. Prefer salt-call
kinetic_identity.disable_inactive for G2. This script talks to OpenSearch
and OpenLDAP with StartTLS using environment variables (no secrets in the
image). Image must provide ldap3 and requests.
"""

import json
import os
import re
import ssl
import sys
from datetime import datetime, timedelta

import requests
from ldap3 import ALL, MODIFY_REPLACE, SUBTREE, Connection, Server, Tls


def env(name, default=""):
    return os.environ.get(name, default)


def parse_generalized_time(value):
    if not value:
        return None
    text = str(value).rstrip("Z").split(".", 1)[0]
    for length, fmt in ((14, "%Y%m%d%H%M%S"), (12, "%Y%m%d%H%M"), (8, "%Y%m%d")):
        if len(text) >= length:
            try:
                return datetime.strptime(text[:length], fmt)
            except ValueError:
                continue
    return None


def recent_logins(cfg):
    body = {
        "size": 0,
        "track_total_hits": True,
        "query": {
            "bool": {
                "must": [
                    {"term": {cfg["event_type_field"]: cfg["event_type_value"]}},
                    {"range": {cfg["timestamp_field"]: {"gte": "now-%sd" % cfg["inactive_days"]}}},
                ]
            }
        },
        "aggs": {
            "by_username": {"terms": {"field": cfg["username_field"], "size": 10000}},
            "by_userid": {"terms": {"field": cfg["user_id_field"], "size": 10000}},
        },
    }
    response = requests.post(
        "{0}/{1}/_search".format(cfg["opensearch_host"].rstrip("/"), cfg["index"]),
        auth=(cfg["opensearch_user"], cfg["opensearch_password"]),
        json=body,
        verify=False,
        timeout=60,
    )
    response.raise_for_status()
    data = response.json()
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
    return hits, usernames, userids


def main():
    cfg = {
        "inactive_days": int(env("INACTIVE_DAYS", "90")),
        "grace_days": int(env("GRACE_DAYS", "7")),
        "dry_run": env("DRY_RUN", "true").lower() in ("1", "true", "yes"),
        "users_base_dn": env("USERS_BASE_DN"),
        "exclude_uids": [x for x in env("EXCLUDE_UIDS").split(",") if x],
        "exclude_dns": [x for x in env("EXCLUDE_DNS").split(",") if x],
        "exclude_uid_regex": env("EXCLUDE_UID_REGEX"),
        "index": env("OPENSEARCH_INDEX", "keycloak-logs-*"),
        "event_type_field": env("EVENT_TYPE_FIELD", "type.keyword"),
        "event_type_value": env("EVENT_TYPE_VALUE", "LOGIN"),
        "user_id_field": env("USER_ID_FIELD", "userId.keyword"),
        "username_field": env("USERNAME_FIELD", "details.username.keyword"),
        "timestamp_field": env("TIMESTAMP_FIELD", "time"),
        "opensearch_host": env(
            "OPENSEARCH_HOST", "https://api.logger.services.gacyberrange.org:443"
        ),
        "opensearch_user": env("OPENSEARCH_USERNAME", "admin"),
        "opensearch_password": env("OPENSEARCH_PASSWORD"),
        "allow_empty": env("ALLOW_EMPTY_LOGIN_INDEX", "false").lower()
        in ("1", "true", "yes"),
        "ldap_url": env("LDAP_URL"),
        "ldap_bind_dn": env("LDAP_BIND_DN"),
        "ldap_bind_password": env("LDAP_BIND_PASSWORD"),
        "ldap_ca": env("LDAP_CA_FILE", "/tls/ca.pem"),
        "user_filter": env("USER_FILTER", "(objectClass=inetOrgPerson)"),
    }
    hits, usernames, userids = recent_logins(cfg)
    if hits == 0 and not cfg["allow_empty"]:
        print(
            "No LOGIN events in {0} for {1}d; refusing to disable anyone".format(
                cfg["index"], cfg["inactive_days"]
            )
        )
        return 2

    tls = Tls(ca_certs_file=cfg["ldap_ca"], validate=ssl.CERT_REQUIRED)
    server = Server(cfg["ldap_url"], use_ssl=False, get_info=ALL, tls=tls)
    conn = Connection(
        server,
        user=cfg["ldap_bind_dn"],
        password=cfg["ldap_bind_password"],
        auto_bind=False,
    )
    conn.open()
    conn.start_tls()
    if not conn.bind():
        print("LDAP bind failed: {0}".format(conn.result))
        return 1

    conn.search(
        cfg["users_base_dn"],
        cfg["user_filter"],
        search_scope=SUBTREE,
        attributes=["uid", "entryUUID", "createTimestamp", "pwdAccountLockedTime"],
    )
    grace_cutoff = datetime.utcnow() - timedelta(days=cfg["grace_days"])
    would = []
    for entry in conn.entries:
        uid = str(entry.uid) if "uid" in entry else ""
        uuid = str(entry.entryUUID) if "entryUUID" in entry else ""
        dn = entry.entry_dn
        if uid in cfg["exclude_uids"] or dn in cfg["exclude_dns"]:
            print("skip uid={0} reason=exclude".format(uid))
            continue
        if cfg["exclude_uid_regex"] and uid and re.search(cfg["exclude_uid_regex"], uid):
            print("skip uid={0} reason=exclude_uid_regex".format(uid))
            continue
        if "pwdAccountLockedTime" in entry and entry.pwdAccountLockedTime:
            print("skip uid={0} reason=already_locked".format(uid))
            continue
        if uid in usernames or uuid in userids:
            print("skip uid={0} reason=recent_login".format(uid))
            continue
        created = parse_generalized_time(
            str(entry.createTimestamp) if "createTimestamp" in entry else ""
        )
        if created and created > grace_cutoff:
            print("skip uid={0} reason=grace_period".format(uid))
            continue
        would.append(dn)
        prefix = "[dry-run] would disable" if cfg["dry_run"] else "disable"
        print("{0} uid={1} dn={2}".format(prefix, uid, dn))
        if not cfg["dry_run"]:
            conn.modify(
                dn,
                {"pwdAccountLockedTime": [(MODIFY_REPLACE, ["000001010000Z"])]},
            )
            if not conn.result.get("success") and conn.result.get("description") != "success":
                print("failed to lock {0}: {1}".format(dn, conn.result))

    print(json.dumps({"dry_run": cfg["dry_run"], "candidates": len(would), "hits": hits}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
