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
1. Update following values in "values/nected-values.yaml" files, according to your ingress.
    - `<<scheme>>`
    - `<<frontend-konark-domain>>`
    - `<<frontend-editor-domain>>`
    - `<<backend-nalanda-domain>>`
    - `<<backend-vidhaan-router-domain>>`
    - `<<ingressClassName>>` (also enable ingress)

2. When installing databases with nected's chart, include datastore in the installation.
   ```
   helm upgrade -i datastore charts/datastore/ -f values/datastore-values.yaml
   ```

3. Now install temporal.
    ```
    helm upgrade -i temporal charts/temporal/ -f values/temporal-values.yaml
    ```

4. Install Nected services.
    ```
    helm upgrade -i nected charts/nected-services/ -f values/nected-values.yaml
    ```

With all services running, access the application through the fronend-konark domain using the default user and password (values/nected-values.yaml).