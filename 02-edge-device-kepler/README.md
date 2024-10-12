# KEPLER - Kubernetes Power Level Exporter

Kepler is used to collect power consumption at k8s resource level (containers). This uses prometheus to get the power level metrics data.

## How to setup kepler exporter in microshift

```shell
oc apply -k 02-edge-device-kepler/kepler-manifests
```

(or)

Use helm chart to deploy kepler in microshift

```shell
helm install 02-edge-device-kepler/kepler-gitops/helm
```
