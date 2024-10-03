# Nected OnPremise
Installation using Helm charts

![Nected Onpremise Architecture](https://assets.nected.ai/nalanda/nected-onpremise-arch.jpg)

## Pre-Requisite
1. An external Application Load Balancer with Ingress.

2. Map 4 domains to loadbalaner
    - `<<ui-domain>>`
    - `<<editor-domain>>`
    - `<<backend-domain>>`
    - `<<router-domain>>`
      - Configure external access only if rule/workflow API or webhook needs to be accessible from outside of cluster.

## Deployment steps
1. Add Nected Repo:
    ```
    helm repo add nected https://nected.github.io/helm-charts
    ```

2. Download sample files into values folder:
    - [Datastore values](https://charts.nected.io/values/datastore-values.yaml)
    - [Temporal values](https://charts.nected.io/values/temporal-values.yaml)
    - [Nected values](https://charts.nected.io/values/nected-values.yaml)

3. Update following values in "values/nected-values.yaml" files, according to your ingress.
    - `<<scheme>>`
    - `<<ui-domain>>`
    - `<<editor-domain>>`
    - `<<backend-domain>>`
    - `<<router-domain>>`
    - `<<ingressClassName>>` (also enable ingress)

4. Install Datastore ElasticSearch / Postgresql / Redis.
   ```
   helm upgrade -i datastore nected/datastore -f values/datastore-values.yaml
   ```

   If you want to use external elastic/psql/redis endpoints then skip installing datastore chart, please update endpoints and credentials in value/*.yaml.

5. To enable encryption of sensitive data, create secret for private key, uncomment existingSecretMap key in nected-values.yaml:
    ```
    openssl genrsa -f4 -out encryption-at-rest 4096
    kubectl create secret generic encryption-at-rest-secret --from-file encryption-at-rest
    ```


6.  Install temporal.
    ```
    helm upgrade -i temporal nected/temporal -f values/temporal-values.yaml
    ```

7. Install Nected services:
    ```
    helm install nected nected/nected -f values/nected-values.yaml
    ```

With all services running, access the application through the fronend-konark domain using the default user and password (values/nected-values.yaml).
