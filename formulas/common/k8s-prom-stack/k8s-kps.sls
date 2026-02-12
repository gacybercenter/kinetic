kps-values:
  grafana:
    additionalDataSources:
      - name: Loki
        type: loki
        access: proxy
        url: http://loki.monitoring.svc:3100
        isDefault: false
        jsonData:
          maxLines: 1000
    service:
      type: ClusterIP
      port: 80
      targetPort: 3000
    grafana.ini:
      server:
        root_url: "https://metrics-dev.internal.gacyberrange.org"
        # serve_from_sub_path: true
      auth.anonymous:
        enabled: true
        org_name: Main Org.
        org_role: Viewer
    env:
      GF_SERVER_ROOT_URL: "https://metrics-dev.internal.gacyberrange.org"
    #   GF_SERVER_SERVE_FROM_SUB_PATH: "true"
  prometheus:
    service:
      type: ClusterIP
      port: 9090
      targetPort: 9090
    prometheusSpec:
      externalUrl: "https://metrics-dev.internal.gacyberrange.org/prometheus"
      routePrefix: "/prometheus"
      additionalScrapeConfigs:
        - job_name: k8s-guac
          static_configs:
          - targets:
            - 10.101.20.12:9100
        - job_name: libvirt
          static_configs:
          - targets:
            - 10.200.1.176:9177
            - 10.200.1.183:9177
            - 10.200.1.179:9177
        - job_name: compute-nodes
          static_configs:
          - targets:
            - 10.200.1.176:9100
            - 10.200.1.183:9100
            - 10.200.1.179:9100
        - job_name: ceph
          static_configs:
          - targets:
            - 10.100.1.141:9128
        - job_name: vpp
          static_configs:
          - targets:
            - 10.100.0.2:9482
        - job_name: pfsense
          scrape_interval: 25s        
          scrape_timeout: 20s         
          static_configs:
            - targets:
                - 10.100.0.1:161          # this is the device you want to poll
          metrics_path: /snmp
          params:
            module: [pfsense]       # exact name from your snmp.yml
            auth: [public_v1]
          relabel_configs:
            - source_labels: [__address__]
              target_label: __param_target
            - source_labels: [__param_target]
              target_label: instance
            - target_label: __address__
              replacement: snmp-exporter.monitoring.svc.cluster.local:9116   # <-- your exporter service
        - job_name: gpu
          static_configs:
          - targets:
            - 10.100.1.185:9400
        - job_name: "k8s-lancache"
          scrape_interval: 10s
          metrics_path: /query
          params:
            module: ["internal"]
          relabel_configs:
            - source_labels: ["__address__"]
              target_label: "__param_query_name"
            - source_labels: ["__address__"]
              target_label: "instance"
            - target_label: "__address__"
              replacement: "10.201.21.84:15353"
          static_configs:
            - targets:
                - "example.com"
        - job_name: pulp-coredns
          static_configs:
          - targets:
            - 10.201.21.84:9153
kps-ingress-host:
  - host: metrics-dev.internal.gacyberrange.org
    http:
      paths:
        - path: /
          pathType: Prefix
          backend:

            service:
              name: kube-prometheus-stack-grafana
              port:
                number: 80
        - path: /prometheus
          pathType: Prefix
          backend:
            service:
              name: kube-prometheus-stack-prometheus
              port:
                number: 9090
