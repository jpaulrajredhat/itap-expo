# Setting up opentelemetry colletor

Opentelemetry collector is configured to collect infrastructure metrics telemetry data (CPU, memory, filesystem, networks) from RHDE microshift.

##

## How to setup collector in microshift

***Note: Precheck***

1. Before deploying otel collector verify that kepler exporter is deployed.

2. In, collector exporter replace the otlp exporter URL if necessary which will send telemetry data to the remote otlp collector.

   where the otlp exporter in configmap is,

```yaml
    exporters:

      otlp/microshift-metrics:
        endpoint: REMOTE_OTEL_COLLECTOR:4317
        tls:
          insecure: true
          insecure_skip_verify: true
```

- For kustomize manifests file  
Change the exporter endpoint **"REMOTE_OTEL_COLLECTOR"** in [collector-configmap-otelconfig.yaml](./collector-configmap-otelconfig.yaml)

- For helm chart,  
Change otelexporter URL in [configs](./otel-collector-gitops/helm/configs/otel-config.yaml)

Before that check for kubeconfig file of microshift is present ( ~/.kube/config )

```shell
oc apply -k 03-edge-device-opentelemetry-collector/otel-collector-manifests
```

(or)

Use helm chart to deploy collector in microshift

```shell
helm install 03-edge-device-opentelemetry-collector/otel-collector-gitops/helm
```

## Data collected in opentelemetry

The kepler data (power level metrics of each containers and nodes) will be received using prometheus receiver in collector.

```yaml
    prometheus/kepler-powerlevel:
      config:
        scrape_configs:
          - job_name: 'kepler'
            scrape_interval: 2s
            static_configs:
              - targets: 
                  - ${env:K8S_NODE_IP}:9102
                labels: 
                  exported_instance: ${env:K8S_NODE_NAME}
```

To collect infrastructure metrics telemetry data (cpu, memory, ...) of microshift platform using kubeletstats receiver.

```yaml
    kubeletstats/node:
      auth_type: serviceAccount
      collection_interval: 5s
      endpoint: https://${env:K8S_NODE_IP}:10250
      initial_delay: 1s
      insecure_skip_verify: true
      metric_groups:
        - node
      metrics:
        k8s.node.cpu.usage:
          enabled: true
        k8s.node.cpu.utilization:
          enabled: false

    kubeletstats/pod:
      auth_type: serviceAccount
      collection_interval: 5s
      endpoint: https://${env:K8S_NODE_IP}:10250
      initial_delay: 1s
      insecure_skip_verify: true
      metric_groups:
        - pod
      metrics:
        k8s.pod.cpu.usage:
          enabled: true
        k8s.pod.cpu.utilization:
          enabled: false
```