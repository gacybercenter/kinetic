include:
  - /formulas/common/ldapadmin/install

# Test Kubernetes Deployment for Hello World app
hello-world-deployment:
  k8s.kubernetes_deployment_present:
    - name: hello-world
    - namespace: default
    - replicas: 1
    - image: docker.io/library/nginx:alpine
    - labels:
        app: hello-world
    - annotations:
        description: "Test Hello World deployment"
