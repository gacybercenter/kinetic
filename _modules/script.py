import tnsr
hostname = "https://tnsr.internal.gacyberrange.org"
cert = "/home/training/gcc_dev/gcc/data-center/tnsr/rest_api/tnsr-gacyberrange.crt"
key = "/home/training/gcc_dev/gcc/data-center/tnsr/rest_api/tnsr-gacyberrange.key" 
cacert = "/home/training/gcc_dev/gcc/data-center/tnsr/rest_api/tnsr-rest_api.crt"
Session = tnsr.Session(hostname, cert, key, cacert)
Session.get_unbound_config_hosts()
