acng_maintenance:
  local.state.single:
    - tgt: {{ data['id'] }}
    - args:
      - fun: cmd.run
      - name: "http://localhost:3142/acng-report.html?abortOnErrors=aOe&byPath=bP&byChecksum=bS&truncNow=tN&incomAsDamaged=iad&purgeNow=pN&doExpire=Start+Scan+and%2For+Expiration&calcSize=cs&asNeeded=an#bottom"
