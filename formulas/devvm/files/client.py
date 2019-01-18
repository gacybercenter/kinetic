#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import logging
import shlex

from django.conf import settings

from horizon import exceptions
from horizon.utils.memoized import memoized
from openstack_dashboard.api import base

from neutronclient.v2_0 import client as neutron_client
from zunclient import api_versions
from zunclient.common import template_format
from zunclient.common import utils
from zunclient.v1 import client as zun_client

LOG = logging.getLogger(__name__)

CONTAINER_CREATE_ATTRS = zun_client.containers.CREATION_ATTRIBUTES
CAPSULE_CREATE_ATTRS = zun_client.capsules.CREATION_ATTRIBUTES
IMAGE_PULL_ATTRS = zun_client.images.PULL_ATTRIBUTES
API_VERSION = api_versions.APIVersion(api_versions.DEFAULT_API_VERSION)


def get_auth_params_from_request(request):
    """Extracts properties needed by zunclient call from the request object.

    These will be used to memoize the calls to zunclient.
    """
    endpoint_override = ""
    try:
        endpoint_override = base.url_for(request, 'container')
    except exceptions.ServiceCatalogException:
        LOG.debug('No Container Management service is configured.')
        return None
    return (
        request.user.username,
        request.user.token.id,
        request.user.tenant_id,
        endpoint_override
    )


@memoized
def zunclient(request):
    (
        username,
        token_id,
        project_id,
        endpoint_override
    ) = get_auth_params_from_request(request)

    LOG.debug('zunclient connection created using the token "%s" and url'
              ' "%s"' % (token_id, endpoint_override))
    c = zun_client.Client(username=username,
                          project_id=project_id,
                          auth_token=token_id,
                          endpoint_override=endpoint_override,
                          api_version=API_VERSION)
    return c


def get_auth_params_from_request_neutron(request):
    """Extracts properties needed by neutronclient call from the request object.

    These will be used to memoize the calls to neutronclient.
    """
    return (
        request.user.token.id,
        base.url_for(request, 'network'),
        base.url_for(request, 'identity')
    )


@memoized
def neutronclient(request):
    (
        token_id,
        neutron_url,
        auth_url
    ) = get_auth_params_from_request_neutron(request)
    insecure = getattr(settings, 'OPENSTACK_SSL_NO_VERIFY', False)
    cacert = getattr(settings, 'OPENSTACK_SSL_CACERT', None)

    LOG.debug('neutronclient connection created using the token "%s" and url'
              ' "%s"' % (token_id, neutron_url))
    c = neutron_client.Client(token=token_id,
                              auth_url=auth_url,
                              endpoint_url=neutron_url,
                              insecure=insecure, ca_cert=cacert)
    return c


def _cleanup_params(attrs, check, **params):
    args = {}
    run = False

    for (key, value) in params.items():
        if key == "run":
            run = value
        elif key == "cpu":
            args[key] = float(value)
        elif key == "memory" or key == "disk":
            args[key] = int(value)
        elif key == "interactive" or key == "mounts" or key == "nets" \
                or key == "security_groups" or key == "hints"\
                or key == "auto_remove" or key == "auto_heal":
            args[key] = value
        elif key == "restart_policy":
            args[key] = utils.check_restart_policy(value)
        elif key == "environment" or key == "labels":
            values = {}
            vals = value.split(",")
            for v in vals:
                kv = v.split("=", 1)
                values[kv[0]] = kv[1]
            args[str(key)] = values
        elif key == "command":
            args[key] = shlex.split(value)
        elif key in attrs:
            if value is None:
                value = ''
            args[str(key)] = str(value)
        elif check:
            raise exceptions.BadRequest(
                "Key must be in %s" % ",".join(attrs))

    return args, run


def _delete_attributes_with_same_value(old, new):
    '''Delete attributes with same value from new dict

    If new dict has same value in old dict, remove the attributes
    from new dict.
    '''
    for k in old.keys():
        if k in new:
            if old[k] == new[k]:
                del new[k]
    return new


def container_create(request, **kwargs):
    args, run = _cleanup_params(CONTAINER_CREATE_ATTRS, True, **kwargs)
    response = None
    if run:
        response = zunclient(request).containers.run(**args)
    else:
        response = zunclient(request).containers.create(**args)
    return response


def container_update(request, id, **kwargs):
    '''Update Container

    Get current Container attributes and check updates.
    And update with "rename" for "name", then use "update" for
    "cpu" and "memory".
    '''

    # get current data
    container = zunclient(request).containers.get(id).to_dict()
    if container["memory"] is not None:
        container["memory"] = int(container["memory"].replace("M", ""))
    args, run = _cleanup_params(CONTAINER_CREATE_ATTRS, True, **kwargs)

    # remove same values from new params
    _delete_attributes_with_same_value(container, args)

    # do update
    if len(args):
        zunclient(request).containers.update(id, **args)

    return args


def container_delete(request, **kwargs):
    return zunclient(request).containers.delete(**kwargs)


def container_list(request, limit=None, marker=None, sort_key=None,
                   sort_dir=None, detail=True):
    # TODO(shu-mutou): detail option should be added, if it is
    # implemented in Zun API
    return zunclient(request).containers.list(limit, marker, sort_key,
                                              sort_dir)


def container_show(request, id):
    return zunclient(request).containers.get(id)


def container_logs(request, id):
    args = {}
    args["stdout"] = True
    args["stderr"] = True
    return zunclient(request).containers.logs(id, **args)


def container_start(request, id):
    return zunclient(request).containers.start(id)


def container_stop(request, id, timeout):
    return zunclient(request).containers.stop(id, timeout)


def container_restart(request, id, timeout):
    return zunclient(request).containers.restart(id, timeout)


def container_rebuild(request, id, **kwargs):
    return zunclient(request).containers.rebuild(id, **kwargs)


def container_pause(request, id):
    return zunclient(request).containers.pause(id)


def container_unpause(request, id):
    return zunclient(request).containers.unpause(id)


def container_execute(request, id, command):
    args = {"command": command}
    return zunclient(request).containers.execute(id, **args)


def container_kill(request, id, signal=None):
    return zunclient(request).containers.kill(id, signal)


def container_attach(request, id):
    return zunclient(request).containers.attach(id)


def container_resize(request, id, width, height):
    return zunclient(request).containers.resize(id, width, height)


def container_network_attach(request, id):
    network = request.DATA.get("network") or None
    zunclient(request).containers.network_attach(id, network)
    return {"container": id, "network": network}


def container_network_detach(request, id):
    network = request.DATA.get("network") or None
    zunclient(request).containers.network_detach(id, network)
    return {"container": id, "network": network}


def port_update_security_groups(request):
    port = request.DATA.get("port") or None
    security_groups = request.DATA.get("security_groups") or None
    kwargs = {"security_groups": security_groups}
    neutronclient(request).update_port(port, body={"port": kwargs})
    return {"port": port, "security_group": security_groups}


def availability_zone_list(request):
    list = zunclient(request).availability_zones.list()
    return list


def capsule_list(request, limit=None, marker=None, sort_key=None,
                 sort_dir=None):
    return zunclient(request).capsules.list(limit, marker, sort_key,
                                            sort_dir)


def capsule_show(request, id):
    return zunclient(request).capsules.get(id)


def capsule_create(request, **kwargs):
    args, run = _cleanup_params(CAPSULE_CREATE_ATTRS, True, **kwargs)
    args["template"] = template_format.parse(args["template"])
    return zunclient(request).capsules.create(**args)


def capsule_delete(request, **kwargs):
    return zunclient(request).capsules.delete(**kwargs)


def image_list(request, limit=None, marker=None, sort_key=None,
               sort_dir=None, detail=False):
    # FIXME(shu-mutou): change "detail" param to True, if it enabled.
    return zunclient(request).images.list(limit, marker, sort_key,
                                          sort_dir, detail)


def image_create(request, **kwargs):
    args, run = _cleanup_params(IMAGE_PULL_ATTRS, True, **kwargs)
    return zunclient(request).images.create(**args)


def image_delete(request, id, **kwargs):
    return zunclient(request).images.delete(id, **kwargs)


def host_list(request, limit=None, marker=None, sort_key=None,
              sort_dir=None, detail=False):
    return zunclient(request).hosts.list(limit, marker, sort_key,
                                         sort_dir, detail)
