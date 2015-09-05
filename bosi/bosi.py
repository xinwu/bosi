import re
import yaml
import time
import Queue
import random
import argparse
import datetime
import threading
import lib.constants as const
import subprocess32 as subprocess
from lib.node import Node
from lib.helper import Helper
from lib.environment import Environment
from collections import OrderedDict

# queue to store all controller nodes
controller_node_q = Queue.Queue()

# queue to store all nodes
node_q = Queue.Queue()
# copy the node_q to this when original list is created
verify_node_q = Queue.Queue()

# result dict
node_dict = {}
time_dict = {}

def worker_setup_node(q):
    while True:
        node = q.get()
        # copy ivs pkg to node
        Helper.copy_pkg_scripts_to_remote(node)

        # deploy node
        Helper.safe_print("Start to deploy %(hostname)s\n" %
                         {'hostname' : node.hostname})
        if node.cleanup and node.role == const.ROLE_NEUTRON_SERVER:
            Helper.run_command_on_remote(node,
                (r'''sudo bash %(dst_dir)s/%(hostname)s_ospurge.sh >> %(log)s 2>&1''' %
                {'dst_dir'  : node.dst_dir,
                 'hostname' : node.hostname,
                 'log'      : node.log}))

        # a random delay to smooth apt-get/yum
        delay = random.random() * 10.0
        time.sleep(delay)

        start_time = datetime.datetime.now()
        Helper.run_command_on_remote(node,
            (r'''sudo bash %(dst_dir)s/%(hostname)s.sh >> %(log)s 2>&1''' %
            {'dst_dir'  : node.dst_dir,
             'hostname' : node.hostname,
             'log'      : node.log}))
        end_time = datetime.datetime.now()

        # parse setup log
        diff = Helper.timedelta_total_seconds(end_time - start_time)
        node.set_time_diff(diff)
        node = Helper.update_last_log(node)
        node_dict[node.hostname] = node
        time_dict[node.hostname] = diff

        # when deploying T5 on UBUNTU, reboot compute nodes
        Helper.reboot_if_necessary(node)

        Helper.safe_print("Finish deploying %(hostname)s, cost time: %(diff).2f\n" %
                         {'hostname' : node.hostname, 'diff' : node.time_diff})
        q.task_done()

def verify_node_setup(q):
    while True:
        node = q.get()
        all_service_status = 'Service status for node : ' + node.hostname
        # check services are running and IVS version is correct
        if node.deploy_dhcp_agent:
            dhcp_status = Helper.check_os_service_status(node, "neutron-dhcp-agent")
            all_service_status = all_service_status + ' | DHCP Agent ' + dhcp_status
            metadata_status = Helper.check_os_service_status(node, "neutron-metadata-agent")
            all_service_status = all_service_status + ' | Metadata Agent ' + metadata_status
        if node.deploy_l3_agent:
            l3_status = Helper.check_os_service_status(node, "neutron-l3-agent")
            all_service_status = all_service_status + ' | L3 Agent ' + l3_status
        if node.deploy_haproxy:
            lbaas_status = Helper.check_os_service_status(node, "neutron-lbaas-agent")
            all_service_status = all_service_status + ' | LBAAS Agent ' + lbaas_status
        # for T6 deployment, check IVS status and version too
        if node.deploy_mode == const.T6:
            ivs_status = Helper.check_os_service_status(node, "ivs")
            all_service_status = all_service_status + ' | IVS ' + ivs_status
            if ivs_status == ':-)':
                # ivs is OK. check version
                ivs_version = Helper.check_ivs_version(node)
                all_service_status = all_service_status + ' | IVS version ' + ivs_version
        Helper.safe_print(all_service_status + '\n')
        q.task_done()


def deploy_bcf(config, mode, fuel_cluster_id, rhosp, tag, cleanup, verify, verify_only):
    # Deploy setup node
    Helper.safe_print("Start to prepare setup node\n")
    env = Environment(config, mode, fuel_cluster_id, rhosp, tag, cleanup)
    Helper.common_setup_node_preparation(env)
    controller_nodes = []

    # Generate detailed node information
    Helper.safe_print("Start to setup Big Cloud Fabric\n")
    nodes_config = None
    if 'nodes' in config:
        nodes_yaml_config = config['nodes']
    node_dic = Helper.load_nodes(nodes_yaml_config, env)

    # copy neutron config from neutron server to setup node
    for hostname, node in node_dic.iteritems():
        if node.role == const.ROLE_NEUTRON_SERVER:
            controller_nodes.append(node)
    Helper.copy_neutron_config_from_controllers(controller_nodes)
    Helper.copy_dhcp_scheduler_from_controllers(controller_nodes)

    # Generate scripts for each node
    for hostname, node in node_dic.iteritems():
        if node.skip:
            Helper.safe_print("skip node %(hostname)s due to %(error)s\n" %
                             {'hostname' : hostname,
                              'error'    : node.error})
            continue

        if node.tag != node.env_tag:
            Helper.safe_print("skip node %(hostname)s due to mismatched tag\n" %
                             {'hostname' : hostname})
            continue

        if node.os == const.CENTOS:
            Helper.generate_scripts_for_centos(node)
        elif node.os == const.UBUNTU:
            Helper.generate_scripts_for_ubuntu(node)
        elif node.os == const.REDHAT:
            Helper.generate_scripts_for_redhat(node)

        if node.role == const.ROLE_NEUTRON_SERVER:
            controller_node_q.put(node)
        else:
            # python doesn't have deep copy for Queue, hence add to both
            node_q.put(node)
            verify_node_q.put(node)

        if node.rhosp:
            Helper.chmod_node(node)

    for hostname, node in node_dic.iteritems():
        with open(const.LOG_FILE, "a") as log_file:
            log_file.write(str(node))

    # in case of verify_only, do not deploy, just verify
    if not verify_only:
        # Use single thread to setup controller nodes
        t = threading.Thread(target=worker_setup_node, args=(controller_node_q,))
        t.daemon = True
        t.start()
        controller_node_q.join()

        # Use multiple threads to setup compute nodes
        for i in range(const.MAX_WORKERS):
            t = threading.Thread(target=worker_setup_node, args=(node_q,))
            t.daemon = True
            t.start()
        node_q.join()

        sorted_time_dict = OrderedDict(sorted(time_dict.items(), key=lambda x: x[1]))
        for hostname, time in sorted_time_dict.items():
            Helper.safe_print("node: %(node)s, time: %(time).2f, last_log: %(log)s\n" %
                              {'node' : hostname,
                               'time' : time,
                               'log'  : node_dict[hostname].last_log})

        Helper.safe_print("Big Cloud Fabric deployment finished! Check %(log)s on each node for details.\n" %
                         {'log' : const.LOG_FILE})

    if verify or verify_only:
        # verify each node and post results
        Helper.safe_print("Verifying deployment for all compute nodes.\n")
        for i in range(const.MAX_WORKERS):
            t = threading.Thread(target=verify_node_setup, args=(verify_node_q,))
            t.daemon = True
            t.start()
        verify_node_q.join()

def main():
    # Check if network is working properly
    code = subprocess.call("ping www.bigswitch.com -c1", shell=True)
    if code != 0:
        Helper.safe_print("Network is not working properly, quit deployment\n")
        exit(1)

    # Parse configuration
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--config-file", required=True,
                        help="BCF YAML configuration file")
    parser.add_argument("-m", "--deploy-mode", required=True,
                        help="pfabric or pvfabric"),
    parser.add_argument('-f', "--fuel-cluster-id", required=False,
                        help="Fuel cluster ID. Fuel settings may override YAML configuration. Please refer to config.yaml")
    parser.add_argument('-r', "--rhosp", action='store_true', default=False,
                        help="red hat openstack director is the installer.")
    parser.add_argument('-t', "--tag", required=False,
                        help="Deploy to tagged nodes only.")
    parser.add_argument('--cleanup', action='store_true', default=False,
                        help="Clean up existing routers, networks and projects.")
    parser.add_argument('--verify', action='store_true', default=False,
                        help="Verify service status for compute nodes after deployment.")
    parser.add_argument('--verifyonly', action='store_true', default=False,
                        help="Verify service status for compute nodes after deployment. Does not deploy BCF specific changes.")
    args = parser.parse_args()
    if args.fuel_cluster_id and args.rhosp:
        Helper.safe_print("Cannot have both fuel and rhosp as openstack installer.\n")
        return
    if args.deploy_mode not in const.MODE_DICT:
        Helper.safe_print("Deploy mode has to be pfabric or pvfabric.\n")
        return
    with open(args.config_file, 'r') as config_file:
        config = yaml.load(config_file)
    deploy_bcf(config, args.deploy_mode, args.fuel_cluster_id, args.rhosp, args.tag, args.cleanup, args.verify, args.verifyonly)


if __name__=='__main__':
    main()


