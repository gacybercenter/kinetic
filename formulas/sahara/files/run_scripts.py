# Copyright (c) 2014 Mirantis Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os

from oslo_log import log as logging

from sahara.plugins import context
from sahara.plugins import edp
from sahara.plugins import utils
from sahara_plugin_vanilla.i18n import _
from sahara_plugin_vanilla.plugins.vanilla.hadoop2 import config_helper
from sahara_plugin_vanilla.plugins.vanilla.hadoop2 import oozie_helper
from sahara_plugin_vanilla.plugins.vanilla.hadoop2 import utils as u
from sahara_plugin_vanilla.plugins.vanilla import utils as vu

LOG = logging.getLogger(__name__)


def start_dn_nm_processes(instances):
    filternames = ['datanode', 'nodemanager']
    instances = utils.instances_with_services(instances, filternames)

    if len(instances) == 0:
        return

    utils.add_provisioning_step(
        instances[0].cluster_id,
        utils.start_process_event_message("DataNodes, NodeManagers"),
        len(instances))

    with context.PluginsThreadGroup() as tg:
        for instance in instances:
            with context.set_current_instance_id(instance.instance_id):
                processes = set(instance.node_group.node_processes)
                processes = processes.intersection(filternames)
                tg.spawn('vanilla-start-processes-%s' % instance.instance_name,
                         _start_processes, instance, list(processes))


@utils.event_wrapper(True)
def _start_processes(instance, processes):
    with instance.remote() as r:
        if 'datanode' in processes:
            r.execute_command(
                'sudo su - -c "hadoop-daemon.sh start datanode" hadoop')
        if 'nodemanager' in processes:
            r.execute_command(
                'sudo su - -c  "yarn-daemon.sh start nodemanager" hadoop')


def start_hadoop_process(instance, process):
    instance.remote().execute_command(
        'sudo su - -c "hadoop-daemon.sh start %s" hadoop' % process)


def start_yarn_process(instance, process):
    instance.remote().execute_command(
        'sudo su - -c  "yarn-daemon.sh start %s" hadoop' % process)


@utils.event_wrapper(
    True, step=utils.start_process_event_message("HistoryServer"))
def start_historyserver(instance):
    instance.remote().execute_command(
        'sudo su - -c "mr-jobhistory-daemon.sh start historyserver" hadoop')


@utils.event_wrapper(True, step=utils.start_process_event_message("Oozie"))
def start_oozie_process(pctx, instance):
    with context.set_current_instance_id(instance.instance_id):
        with instance.remote() as r:
            if config_helper.is_mysql_enabled(pctx, instance.cluster):
                _start_mysql(r)
                LOG.debug("Creating Oozie DB Schema")
                sql_script = utils.get_file_text(
                    'plugins/vanilla/hadoop2/resources/create_oozie_db.sql',
                    'sahara_plugin_vanilla')

                password = oozie_helper.get_oozie_mysql_configs(
                    instance.cluster)[
                    'oozie.service.JPAService.jdbc.password']
                sql_script = sql_script.replace("password", password)

                script_location = "create_oozie_db.sql"
                r.write_file_to(script_location, sql_script)
                r.execute_command('mysql -u root < %(script_location)s && '
                                  'rm %(script_location)s' %
                                  {"script_location": script_location})

            _oozie_share_lib(r)
            _start_oozie(r)


@utils.event_wrapper(
    True, step=utils.start_process_event_message("Spark History Server"))
def start_spark_history_server(master):
    sp_home = config_helper.get_spark_home(master.cluster)
    with context.set_current_instance_id(master.instance_id):
        with master.remote() as r:
            r.execute_command('sudo su - -c "bash %s" hadoop' % os.path.join(
                sp_home, 'sbin/start-history-server.sh'))


def start_zk_server(instances):
    utils.add_provisioning_step(
        instances[0].cluster_id,
        utils.start_process_event_message("ZooKeeper"),
        len(instances))

    with context.PluginsThreadGroup() as tg:
        for instance in instances:
            with context.set_current_instance_id(instance.instance_id):
                tg.spawn('ZK-start-processes-%s' % instance.instance_name,
                         _start_zk_processes, instance, 'start')


def refresh_zk_servers(cluster, to_delete_instances=None):
    instances = vu.get_zk_servers(cluster)
    if to_delete_instances:
        for instance in to_delete_instances:
            if instance in instances:
                instances.remove(instance)

    utils.add_provisioning_step(
        cluster.id,
        utils.start_process_event_message("ZooKeeper"),
        len(instances))

    with context.PluginsThreadGroup() as tg:
        for instance in instances:
            with context.set_current_instance_id(instance.instance_id):
                tg.spawn('ZK-restart-processes-%s' % instance.instance_name,
                         _start_zk_processes, instance, 'restart')


@utils.event_wrapper(True)
def _start_zk_processes(instance, operation):
    with instance.remote() as r:
        r.execute_command(
            'sudo su - -c "bash /opt/zookeeper/bin/zkServer.sh %s"'
            ' hadoop' % operation)


def format_namenode(instance):
    instance.remote().execute_command(
        'sudo su - -c "hdfs namenode -format" hadoop')


@utils.event_wrapper(
    True,
    step=utils.start_process_event_message("Oozie"), param=('cluster', 0))
def refresh_hadoop_nodes(cluster):
    nn = vu.get_namenode(cluster)
    nn.remote().execute_command(
        'sudo su - -c "hdfs dfsadmin -refreshNodes" hadoop')


@utils.event_wrapper(
    True, step=_("Refresh %s nodes") % "YARN", param=('cluster', 0))
def refresh_yarn_nodes(cluster):
    rm = vu.get_resourcemanager(cluster)
    rm.remote().execute_command(
        'sudo su - -c "yarn rmadmin -refreshNodes" hadoop')


def _oozie_share_lib(remote):
    LOG.debug("Sharing Oozie libs")
    # remote.execute_command('sudo su - -c "/opt/oozie/bin/oozie-setup.sh '
    #                        'sharelib create -fs hdfs://%s:8020" hadoop'
    #                        % nn_hostname)

    # TODO(alazarev) return 'oozie-setup.sh sharelib create' back
    # when #1262023 is resolved

    remote.execute_command(
        'sudo su - -c "mkdir /tmp/oozielib && '
        'tar zxf /opt/oozie/oozie-sharelib-*.tar.gz -C '
        '/tmp/oozielib && '
        'hadoop fs -mkdir /user && '
        'hadoop fs -mkdir /user/hadoop && '
        'hadoop fs -put /tmp/oozielib/share /user/hadoop/ && '
        'rm -rf /tmp/oozielib" hadoop')

    LOG.debug("Creating sqlfile for Oozie")
    remote.execute_command('sudo su - -c "/opt/oozie/bin/ooziedb.sh '
                           'create -sqlfile oozie.sql '
                           '-run Validate DB Connection" hadoop')


def _start_mysql(remote):
    LOG.debug("Starting mysql")
    remote.execute_command('/opt/start-mysql.sh')


def _start_oozie(remote):
    remote.execute_command(
        'sudo su - -c "/opt/oozie/bin/oozied.sh start" hadoop')


@utils.event_wrapper(
    True, step=_("Await %s start up") % "DataNodes", param=('cluster', 0))
def await_datanodes(cluster):
    datanodes_count = len(vu.get_datanodes(cluster))
    if datanodes_count < 1:
        return

    l_message = _("Waiting on %s datanodes to start up") % datanodes_count
    with vu.get_namenode(cluster).remote() as r:
        utils.plugin_option_poll(
            cluster, _check_datanodes_count,
            config_helper.DATANODES_STARTUP_TIMEOUT, l_message, 1, {
                'remote': r, 'count': datanodes_count})


def _check_datanodes_count(remote, count):
    if count < 1:
        return True

    LOG.debug("Checking datanode count")
    exit_code, stdout = remote.execute_command(
        'sudo su -lc "hdfs dfsadmin -report" hadoop | '
        r'grep "Live datanodes\|Datanodes available:" | '
        r'grep -o "[0-9]\+" | head -n 1')
    LOG.debug("Datanode count='{count}'".format(count=stdout.rstrip()))

    return exit_code == 0 and stdout and int(stdout) == count


def _hive_create_warehouse_dir(remote):
    LOG.debug("Creating Hive warehouse dir")
    remote.execute_command("sudo su - -c 'hadoop fs -mkdir -p "
                           "/user/hive/warehouse' hadoop")


def _hive_copy_shared_conf(remote, dest):
    LOG.debug("Copying shared Hive conf")
    dirname, filename = os.path.split(dest)
    remote.execute_command(
        "sudo su - -c 'hadoop fs -mkdir -p %s && "
        "hadoop fs -put /opt/hive/conf/hive-site.xml "
        "%s' hadoop" % (dirname, dest))


def _hive_create_db(remote):
    LOG.debug("Creating Hive metastore db")
    remote.execute_command("mysql -u root < /tmp/create_hive_db.sql")


def _hive_metastore_start(remote):
    LOG.debug("Starting Hive Metastore Server")
    remote.execute_command("sudo su - -c 'nohup /opt/hive/bin/hive"
                           " --service metastore > /dev/null &' hadoop")


@utils.event_wrapper(
    True, step=utils.start_process_event_message("HiveServer"))
def start_hiveserver_process(pctx, instance):
    with context.set_current_instance_id(instance.instance_id):
        with instance.remote() as r:
            _hive_create_warehouse_dir(r)
            _hive_copy_shared_conf(
                r, edp.get_hive_shared_conf_path('hadoop'))

            if config_helper.is_mysql_enabled(pctx, instance.cluster):
                oozie = vu.get_oozie(instance.node_group.cluster)
                if not oozie or instance.hostname() != oozie.hostname():
                    _start_mysql(r)

                version = instance.cluster.hadoop_version
                sql_script = utils.get_file_text(
                    'plugins/vanilla/v{}/resources/create_hive_db.sql'.format(
                        version.replace('.', '_')), 'sahara_plugin_vanilla')

                sql_script = sql_script.replace(
                    '{{password}}', u.get_hive_password(instance.cluster))
                r.write_file_to('/tmp/create_hive_db.sql', sql_script)
                _hive_create_db(r)
                _hive_metastore_start(r)
                LOG.info("Hive Metastore server at {host} has been "
                         "started".format(host=instance.hostname()))