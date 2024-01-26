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
    url = f"https://{hostname}/restconf/data/netgate-nat:nat-config/static/mapping-table"
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
    if get_difference:
        different = [entry for entry in current_entries if entry not in new_entries]
        merged_entries['netgate-nat:mapping-table']['mapping-entry'] = different
    # If get_difference is False, return current entries + new entries
    else:
        same = [entry for entry in new_entries if entry not in current_entries]
        same += current_entries
        merged_entries['netgate-nat:mapping-table']['mapping-entry'] = same
    # Return the merged entries
    return merged_entries

### UNBOUND SECTION ###

def unbound_zones_request(method,
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
    url = f"https://{hostname}/restconf/data/netgate-unbound:unbound-config/daemon/server/local-zones"
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

def merge_zones(current_zones,
                new_zones,
                get_difference=False):
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
    # Initialize the dictionary that will store the merged zones
    merged_zones = {'netgate-unbound:local-zones': {'zone': []}}
    # Extract zones from their wrappers
    current_zones = current_zones['netgate-unbound:local-zones']['zone']
    new_zones = new_zones['netgate-unbound:local-zones']['zone']
    # If get_difference is True, return current zones - new zones
    if get_difference:
        different = [entry for entry in current_zones if entry not in new_zones]
        merged_zones['netgate-unbound:local-zones']['zone'] = different
    # If get_difference is False, return current zones + new zones
    else:
        same = [entry for entry in new_zones if entry not in current_zones]
        same += current_zones
        merged_zones['netgate-unbound:local-zones']['zone'] = same
    # Return the merged zones
    return merged_zones
