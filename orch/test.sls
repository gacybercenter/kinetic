echo {{ salt.saltutil.runner('mine.get', tgt='pxe', fun='file.read') }}:
  cmd.run
