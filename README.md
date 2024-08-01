# Nected OnPremise
Installation using Helm charts

![Nected Onpremise Architecture](https://assets.nected.io/nalanda/nected-onpremise-arch.jpg)

## Pre-Requisite
1. An external Application Load Balancer with Ingress.

2. Map 4 domains to loadbalaner
    - `<<frontend-konark-domain>>`
    - `<<frontend-editor-domain>>`
    - `<<backend-nalanda-domain>>`
    - `<<backend-vidhaan-router-domain>>`
      - Configure external access only if rule/workflow API or webhook needs to be accessible from outside of cluster.

## Deployment steps
1. Add Nected Repo:
    ```
    helm repo add nected https://nected.github.io/helm-charts
    ```

2. Download sample files into values folder:
    - [Datastore values](https://charts.nected.io/values/datastore-values.yaml)
    - [Temporal values](https://charts.nected.io/values/temporal-values.yaml)
    - [Nected Services values](https://charts.nected.io/values/nected-services-values.yaml)

3. Update following values in "values/nected-values.yaml" files, according to your ingress.
    - `<<scheme>>`
    - `<<frontend-konark-domain>>`
    - `<<frontend-editor-domain>>`
    - `<<backend-nalanda-domain>>`
    - `<<backend-vidhaan-router-domain>>`
    - `<<ingressClassName>>` (also enable ingress)

4. Install Datastore ElasticSearch / Postgresql / Redis.
   ```
   helm upgrade -i datastore nected/datastore -f values/datastore-values.yaml
   ```

   If you want to use external elastic/psql/redis endpoints then skip installing datastore chart, please update endpoints and credentials in value/*.yaml.

5.  Install temporal.
    ```
    helm upgrade -i temporal nected/temporal -f values/temporal-values.yaml
    ```

7. Install Nected services:
    ```
    helm install nected nected/nected -f values/nected-services-values.yaml
    ```

With all services running, access the application through the fronend-konark domain using the default user and password (values/nected-values.yaml).
