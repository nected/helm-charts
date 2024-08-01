# Nected OnPremise
Installation using Helm charts

![Nected Onpremise Architecture](https://assets.nected.io/nalanda/nected-onpremise-arch.jpg)

## Pre-Requisite
1. An external Application Load Balancer with Ingress.

2. Map 4 domains to loadbalaner
    - `<<ui-domain>>`
    - `<<editor-domain>>`
    - `<<backend-domain>>`
    - `<<router-domain>>`
      - Configure external access only if rule/workflow API or webhook needs to be accessible from outside of cluster.


## Deployment steps
1. Update following values in "values/nected-values.yaml" files, according to your ingress.
    - `<<scheme>>`
    - `<<ui-domain>>`
    - `<<editor-domain>>`
    - `<<backend-domain>>`
    - `<<router-domain>>`
    - `<<ingressClassName>>` (also enable ingress)

2. Install Datastore ElasticSearch / Postgresql / Redis.
   ```
   helm upgrade -i datastore charts/datastore/ -f values/datastore-values.yaml
   ```

   If you want to use external elastic/psql/redis endpoints then skip installing datastore chart, please update endpoints and credentials in value/*.yaml.

3. Now install temporal.
    ```
    helm upgrade -i temporal charts/temporal/ -f values/temporal-values.yaml
    ```

4. Install Nected services.
    ```
    helm upgrade -i nected charts/nected-services/ -f values/nected-values.yaml
    ```

With all services running, access the application through the fronend-konark domain using the default user and password (values/nected-values.yaml).