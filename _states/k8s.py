# -*- coding: utf-8 -*-
"""
SaltStack state module for managing Kubernetes secrets using kinetic-k8s execution module.
"""

from salt.exceptions import SaltInvocationError

__virtualname__ = 'k8s_secret'

def __virtual__():
    """
    Check if the kinetic-k8s execution module is available.
    """
    if 'kinetic-k8s.uuids_secret_present' in __salt__:
        return __virtualname__
    return (False, 'The kinetic-k8s execution module is not available.')

def uuids_present(name, namespace, secret_name, pillar_data=None, pillar_key=None, deployment_name="salt-master"):
    """
    Ensure that a Kubernetes Secret with UUIDs is present and matches the desired state.
    If the secret is updated, the specified deployment will be restarted.

    name
        The name of the state (arbitrary, for SaltStack identification).

    namespace
        The Kubernetes namespace where the Secret and Deployment reside.

    secret_name
        The name of the Secret in Kubernetes.

    pillar_data
        Optional. Direct pillar data dictionary containing the UUIDs under 'salt-master:uuids'.
        If not provided, data will be fetched using pillar_key.

    pillar_key
        Optional. The pillar key to fetch the data from (e.g., 'salt-master').
        Used if pillar_data is not provided.

    deployment_name
        Optional. The name of the deployment to restart if the secret is updated. Defaults to 'salt-master'.

    Example:
    .. code-block:: yaml

        ensure_uuids_secret:
          k8s_secret.uuids_present:
            - namespace: baremetal-operator-system
            - secret_name: salt-master-uuids
            - pillar_key: salt-master
            - deployment_name: salt-master
    """
    ret = {'name': name, 'result': False, 'comment': '', 'changes': {}}

    try:
        # If pillar_data is not provided, fetch it using pillar_key
        if pillar_data is None:
            if pillar_key is None:
                raise SaltInvocationError('Either pillar_data or pillar_key must be provided.')
            pillar_data = __salt__['pillar.get'](pillar_key, {})

        # Call the execution module function
        result = __salt__['kinetic-k8s.uuids_secret_present'](namespace, secret_name, pillar_data, deployment_name)

        ret['result'] = result['success']
        ret['comment'] = result['message']
        if result['updated']:
            ret['changes'] = {
                'updated': True,
                'restarted': result['restarted'],
                'message': result['message']
            }
        else:
            ret['changes'] = {'updated': False, 'restarted': False, 'message': 'No changes needed'}

    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to ensure Secret {secret_name}: {str(e)}"
        ret['changes'] = {}

    return ret