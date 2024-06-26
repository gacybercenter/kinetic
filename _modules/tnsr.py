"""
Copyright 2020 Augusta University

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

tnsr module - helper functions for tnsr state module
could potentially be fleshed out and become formal fully-featured
salt module
"""

import requests

__virtualname__ = 'tnsr'

def __virtual__():
    return __virtualname__

### NAT SECTION ###

def nat_entries_request(method,
                        cert,
                        key,
                        hostname,
                        cacert=False,
                        payload=None,
                        timeout=60):
    """
    A function to make requests to a REST API endpoint for NAT entries.

    Args:
    - method (str): The HTTP request method, e.g. 'GET', 'POST', 'PUT', etc.
    - cert (str): The path to the certificate file used for authentication.
    - key (str): The path to the key file used for authentication.
    - cacert (bool): Whether to verify the SSL certificate of the API endpoint.
    - payload (str): The payload to include in the request body (optional).
    - hostname (str): The URL of the API endpoint (defaults to a specific value).
    - timeout (int): The number of seconds to wait for a response from the API 
    endpoint before timing out.

    Returns:
    str: The response text from the API endpoint.
    """
    url = f"https://{hostname}/restconf/data/netgate-nat:nat-config/netgate-nat:static/netgate-nat:mapping-table"
    headers={'Content-Type': 'application/yang-data+json'}
    response = requests.request(method,
                                url,
                                cert=(cert, key),
                                verify=cacert,
                                headers=headers,
                                data=payload,
                                timeout=timeout)
    if method != 'GET':
        return response
    return response.text


def merge_entries(current_entries,
                new_entries,
                get_difference=False):
    """Merges two dictionaries containing mapping entries.

    This function takes two dictionaries containing mapping entries and merges them
    into a single dictionary. The merging process can be done in two ways:
        1. get_difference = True: returns the current_entries not in new_entries.
        2. get_difference = False (default): returns the current_entries plus the
        new_entries that are not in current_entries.

    Args:
        current_entries (dict): A dictionary containing current mapping entries.
        new_entries (dict): A dictionary containing new mapping entries.
        get_difference (bool, optional): If True, returns current_entries - new_entries.
            If False, returns current_entries + new_entries. Defaults to False.

    Returns:
        dict: A dictionary containing the merged mapping entries.
    """
    # Initialize the dictionary that will store the merged entries
    merged_entries = {'netgate-nat:mapping-table': {'mapping-entry': []}}
    # Extract entries from their wrappers
    current_entries = current_entries['netgate-nat:mapping-table']['mapping-entry']
    new_entries = new_entries['netgate-nat:mapping-table']['mapping-entry']
    # If get_difference is True, return current entries - new entries

    new_external_addresses = [entry['external-address'] for entry in new_entries]
    entries = [entry for entry in current_entries if entry['external-address'] not in new_external_addresses]
    entries += new_entries
    merged_entries['netgate-nat:mapping-table']['mapping-entry'] = entries
    # Return the merged entries
    return merged_entries

### UNBOUND SECTION ###

def update_hostnames(current_hosts, new_hosts):
    current_hosts_dict = {host['host-name']: host for host in current_hosts}
    for new_host in new_hosts:
        host_name = new_host['host-name']
        if host_name in current_hosts_dict:
            # Update existing host
            current_hosts_dict[host_name].update(new_host)
        else:
            # Add new host
            current_hosts.append(new_host)
    return current_hosts

def update_zones(type, current_zones, new_zones):
    new_zones_dict = {zone['zone-name']: zone for zone in new_zones}
    updated_zones = []  # Create a new list to hold the updated zones
    for current_zone in current_zones:
        zone_name = current_zone['zone-name']
        if zone_name in new_zones_dict:
            if type == "local-zone":
                # Update hosts within the zone
                new_hosts = new_zones_dict[zone_name]['hosts']['host']
                current_hosts = current_zone['hosts']['host']
                current_zone['hosts']['host'] = update_hostnames(current_hosts, new_hosts)
                updated_zones.append(current_zone)  # Add updated current zone
                # Remove the zone from new_zones_dict to avoid re-adding it later
                del new_zones_dict[zone_name]
            elif type == "forward-zone":
                updated_zones.append(new_zones_dict[zone_name])
        else:
            updated_zones.append(current_zone)  # Add current zone as is

    # Add any completely new zones not in current_zones
    if type == "local-zone":
        updated_zones.extend(new_zones_dict.values())  # Add remaining new zones

    return updated_zones

def unbound_zones_request(method,
                        type,
                        cert,
                        key,
                        hostname,
                        cacert=False,
                        payload=None,
                        timeout=10):
    """
    A function to make requests to a REST API endpoint for Unbound zones.
    
    :param method: The HTTP method to use for the request
    (e.g. "GET", "POST", "PUT", "DELETE").
    :param cert: A tuple containing the path to the client certificate and key file.
    :param key: A string containing the client certificate key.
    :param cacert: A Boolean indicating whether to verify the certificate of the server.
    :param payload: (optional) A string or bytes object containing the request payload.
    :param hostname: (optional) The URL of the REST endpoint to request.
    :return: The response text from the server.
    """
    if type == "local-zone":
        url = f"https://{hostname}/restconf/data/netgate-unbound:unbound-config/netgate-unbound:daemon/netgate-unbound:server/netgate-unbound:local-zones"
    elif type == "forward-zone":
        url = f"https://{hostname}/restconf/data/netgate-unbound:unbound-config/netgate-unbound:daemon/netgate-unbound:forward-zones"
    headers={'Content-Type': 'application/yang-data+json'}
    response = requests.request(method,
                                url,
                                cert=(cert, key),
                                verify=cacert,
                                headers=headers,
                                data=payload,
                                timeout=timeout)
    if method != 'GET':
        return response
    return response.text

def merge_zones(type,
                current_zones,
                new_zones):
    """Merges two dictionaries containing DNS zones.

    This function takes two dictionaries containing DNS zones and merges them
    into a single dictionary. The merging process can be done in two ways:
        1. get_difference = True: returns the current_zones not in new_zones.
        2. get_difference = False (default): returns the current_zones plus the
        new_zones that are not in current_zones.

    Args:
        current_zones (dict): A dictionary containing current DNS zones.
        new_zones (dict): A dictionary containing new DNS zones.
        get_difference (bool, optional): If True, returns current_zones - new_zones.
            If False, returns current_zones + new_zones. Defaults to False.

    Returns:
        dict: A dictionary containing the merged DNS zones.
    """

    if type == "local-zone":
        # Initialize the dictionary that will store the merged zones
        merged_zones = {'netgate-unbound:local-zones': {'zone': []}}
        # Extract zones from their wrappers
        current_zones = current_zones['netgate-unbound:local-zones']['zone']
        new_zones = new_zones['netgate-unbound:local-zones']['zone']

        updated_zones = update_zones(type,
                                     current_zones,
                                     new_zones)

        merged_zones['netgate-unbound:local-zones']['zone'] = updated_zones
    elif type == "forward-zone":
        # Initialize the dictionary that will store the merged zones
        merged_zones = {'netgate-unbound:forward-zones': {'zone': []}}
        # Extract zones from their wrappers
        current_zones = current_zones['netgate-unbound:forward-zones']['zone']
        new_zones = new_zones['netgate-unbound:forward-zones']['zone']

        updated_zones = update_zones(type,
                                     current_zones,
                                     new_zones)

        merged_zones['netgate-unbound:forward-zones']['zone'] = updated_zones
    # Return the merged zones
    return merged_zones
