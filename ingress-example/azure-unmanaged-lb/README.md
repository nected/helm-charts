# Commands to Deploy application with tls using cert-manager (Letsencrypt)
## Create DNS Zone
```
az network dns zone create --name <zone name> -resource-group <group name>
```

## Enable nginx
```
az aks approuting enable --resource-group <group name> --name <cluster name>
```

## Get Public IP Address for DNS Zone Mapping
```
kubectl -n app-routing-system get svc nginx
```
- save the IP Address under `EXTERNAL`
- create DNS A record for <DOMAIN_NAME> and <IP_ADDRESS>
- this is mandatory in case of certificate creation using cert manager

## Install cert-manager

```
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade cert-manager jetstack/cert-manager \
    --install \
    --create-namespace \
    --wait \
    --namespace cert-manager \
    --set installCRDs=true
```

## Create ClusterIssuer resource
```
kubectl apply -f cluster-issuer.yaml
```

## Create sample application
```
helm repo add ealenn https://ealenn.github.io/charts
helm install my-echo-server ealenn/echo-server --version 0.5.0 -f sample-echo-values.yaml
```