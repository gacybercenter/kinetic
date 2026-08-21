# -*- coding: utf-8 -*-
"""
SaltStack state module for managing Netplan configurations.

This module provides states for generating and applying Netplan configurations
with support for bonds, bridges, and different host types.
"""


def __virtual__():
    """
    Check if the kinetic_netplan execution module is available.
    """
    if 'kinetic_netplan.generate_config' in __salt__:
        return 'kinetic_netplan'
    return (False, 'The kinetic_netplan execution module is not available.')


def config_present(name, pillar_key='res-k8s', apply_immediately=False):
    """
    Ensure Netplan configuration is present and matches the desired state.

    name
        The name of the state (arbitrary, for SaltStack identification).

    pillar_key
        The pillar key containing the network configuration. Defaults to 'res-k8s'.

    apply_immediately
        Whether to apply the configuration immediately. Defaults to False.

    Example:
    .. code-block:: yaml

        ensure_netplan_config:
          kinetic_netplan.config_present:
            - pillar_key: res-k8s
            - apply_immediately: True
    """
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        # Generate configuration from pillar
        config_result = __salt__['kinetic_netplan.generate_config']()
        
        if not config_result['success']:
            ret['result'] = False
            ret['comment'] = config_result['message']
            return ret

        if apply_immediately:
            # Apply configuration
            apply_result = __salt__['kinetic_netplan.apply_config'](config=config_result['config'])
            
            if apply_result['success']:
                ret['result'] = True
                ret['comment'] = apply_result['message']
                ret['changes'] = apply_result.get('changes', {})
            else:
                ret['result'] = False
                ret['comment'] = apply_result['message']
        else:
            # Just check/generate without applying
            ret['result'] = True
            ret['comment'] = 'Netplan configuration generated (not applied)'
            ret['changes'] = {'config_generated': True}

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f'Failed to ensure Netplan configuration: {str(e)[:100]}...'
        ret['changes'] = {}

    return ret


def promisc_mode_enabled(name, networks=None):
    """
    Ensure promiscuous mode is enabled on specified networks.

    name
        The name of the state (arbitrary, for SaltStack identification).

    networks
        List of network names to enable promiscuous mode on.
        If None, uses all non-management networks from pillar.

    Example:
    .. code-block:: yaml

        ensure_promisc_mode:
          kinetic_netplan.promisc_mode_enabled:
            - networks:
              - sfe
              - sbe
              - priv
    """
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        result = __salt__['kinetic_netplan.promisc_mode'](networks=networks)
        
        if result['success']:
            ret['result'] = True
            ret['comment'] = result['message']
            ret['changes'] = {'promisc_enabled': networks or 'all non-management'}
        else:
            ret['result'] = False
            ret['comment'] = result['message']
            ret['changes'] = {}

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f'Failed to enable promiscuous mode: {str(e)[:100]}...'
        ret['changes'] = {}

    return ret
