# -*- coding: utf-8 -*-
"""
Salt runner for identity lifecycle jobs.

# Implements: 800-171 3.5.6
"""

import logging

log = logging.getLogger(__name__)


def disable_inactive(tgt="*", tgt_type="glob", dry_run=None, inactive_days=None):
    """
    Run kinetic_identity.disable_inactive on a minion that has LDAP and
    OpenSearch access.

    CLI Example:

        salt-run identity.disable_inactive dry_run=True
    """
    kwargs = {}
    if dry_run is not None:
        kwargs["dry_run"] = dry_run
    if inactive_days is not None:
        kwargs["inactive_days"] = inactive_days
    return __salt__["cmd"](
        tgt,
        "kinetic_identity.disable_inactive",
        kwarg=kwargs,
        tgt_type=tgt_type,
    )
