from kubernetes import client, config
from kubernetes.client.rest import ApiException

def get_mac_by_interface_name(namespace, resource_name, interface_name):
    try:
        # Load kubeconfig file (ensure you have access to your cluster config)
        config.load_kube_config()
        # Or use config.load_incluster_config() if running inside a pod
        
        # Create an instance of the Custom Objects API
        custom_api = client.CustomObjectsApi()
        
        # Get the HardwareData resource
        group = "metal3.io"
        version = "v1alpha1"
        plural = "hardwaredatas"
        
        resource = custom_api.get_namespaced_custom_object(
            group=group,
            version=version,
            namespace=namespace,
            plural=plural,
            name=resource_name
        )
        
        # Extract the NICs from the hardware spec
        nics = resource.get('spec', {}).get('hardware', {}).get('nics', [])
        
        # Search for the interface by name
        for nic in nics:
            if nic.get('name') == interface_name:
                return nic.get('mac')
        
        return f"No interface found with name: {interface_name}"
    
    except ApiException as e:
        return f"Exception when calling Kubernetes API: {e}"
    except Exception as e:
        return f"An error occurred: {e}"

def main():
    # Configuration
    namespace = "baremetal-operator-system"
    resource_name = "controller-133-32"  # Replace with your resource name
    interface_name = "eth0"  # Replace with the interface name you're looking for
    
    # Get the MAC address
    mac_address = get_mac_by_interface_name(namespace, resource_name, interface_name)
    print(f"MAC Address for interface {interface_name}: {mac_address}")

if __name__ == "__main__":
    main()