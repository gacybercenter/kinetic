import salt.utils.network as network
import salt.modules.file as file

__virtualname__ = 'minionmanage'

def __virtual__():
    return __virtualname__

def populate(path):
	pending = file.readdir(path)
	return file.read(path)
