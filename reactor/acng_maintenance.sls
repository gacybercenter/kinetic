acng_maintenance:
  local.state.single:
    - tgt: {{ data['id'] }}
    - args:
      - fun: cmd.run
      - name: 'curl -s -K /etc/apt-cacher-ng/curl "http://localhost:3142/acng-report.html?byPath=bP&byChecksum=bS&truncNow=tN&incomAsDamaged=iad&purgeNow=pN&doExpire=Start+Scan+and%2For+Expiration&calcSize=cs&asNeeded=an#bottom" > /dev/null'
