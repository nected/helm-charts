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

# Configuration

1. Update following values in "values/nected-values.yaml":
    - `<<scheme>>`
    - `<<ui-domain>>`
    - `<<editor-domain>>`
    - `<<backend-domain>>`
    - `<<router-domain>>`
    - `<<ingressClassName>>` (enable and update ingressClass)

2. To configure Postgresql / Redis update REDIS & DB values in `nected-values.yaml` &  `temporal-values.yaml` or you can install datastore chart:

   ```
   helm upgrade -i datastore charts/datastore/ -f values/datastore-values.yaml
   ```

3. To enable audit log in various services:

   - Update elastic endpoints and credentials in `temporal-values.yaml` & `nected-values.yaml` or enable `elastic` in `datastore-values.yaml`
   - Enable `elasticsearch.external` in `temporal-values.yaml`
   - Enable `ELASTIC_ENABLED` and `AUDIT_LOG_ENABLED` in `nected-values.yaml`


4. Install temporal chart:
    ```
    helm upgrade -i temporal charts/temporal/ -f values/temporal-values.yaml
    ```

5. To enable encryption of sensitive data, create secret for private key, uncomment `existingSecretMap` in `nected-values.yaml`:
    ```
    openssl genrsa -f4 -out encryption-at-rest 4096
    kubectl create secret generic encryption-at-rest-secret --from-file encryption-at-rest
    ```

5. Install Nected chart.
    ```
    helm upgrade -i nected charts/nected/ -f values/nected-values.yaml
    ```

With all services running, access the application through the `<<ui-domain>>` using the default user and password (values/nected-values.yaml).