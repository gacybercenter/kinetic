import json
import logging
import requests
import salt
import salt.runner

log = logging.getLogger(__name__)

__virtualname__ = 'monitor'

def __virtual__():
    return __virtualname__

def salt_local_cmd(args):
    local = salt.client.get_local_client()
    if len(args) == 0:
        return 'No arguments'
    else:
        cmd = args[0]
        if len(args) >= 2:
            tgt = args[1]
            if len(args) >= 3:
                arg = args[2]
                return_data = local.cmd(tgt, cmd, arg)
            else:
                return_data = local.cmd(tgt, cmd)
        else:
            return_data = local.cmd(cmd)
    return return_data

def salt_run_cmd(args):
    opts = salt.config.master_config('/etc/salt/master.d/*')
    runner = salt.runner.RunnerClient(opts)
    if len(args) == 0:
        return 'No arguments'
    else:
        cmd = args[0]
        if len(args) >= 2:
            tgt = args[1]
            if len(args) >= 3:
                arg = args[2]
                return_data = runner.cmd(cmd, [tgt], arg)
            else:
                return_data = runner.cmd(cmd, [tgt])
        else:
            return_data = runner.cmd(cmd)
    return return_data