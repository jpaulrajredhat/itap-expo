# Setting up opentelemetry colletor 

Opentelemetry collector is configured to collect infrastructure metrics telemetry data (CPU, memory, filesystem, networks) from RHDE microshift.

**How to setup collector in microshift**

Before that check for kubeconfig file of microshift is present ( ~/.kube/config ) 


```shell
oc create ns itap-expo
```

```shell
cd edge-device-opentelemetry-collector
```

```shell
oc apply -f collector-secrets-dockercfg.yaml -n itap-expo
```

```shell
oc apply -f collector-role.yaml -n itap-expo
```

```shell
oc apply -f collector-rolebinding.yaml -n itap-expo
```

```shell
oc apply -f collector-serviceaccount.yaml -n itap-expo
```

```shell
oc apply -f collector-configmap-otelconfig.yaml -n itap-expo
```

```shell
oc apply -f collector-deployment.yaml -n itap-expo
```