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
    - Configure external access only if rule/workflow API or webhook needs to be reachable from outside.

3. need to enable storage drivers, e.g: for AKS:
   ```
   az aks update -n <Cluster Name> -g <Resource Group> --enable-disk-driver --enable-file-driver --enable-blob-driver --enable-snapshot-controller
   ```

## Deployment steps
1. Add Nected Repo:
    ```
    helm repo add nected https://nected.github.io/helm-charts
    ```

2. Download sample files into values folder:
    - [Datastore values](https://charts.nected.io/values/datastore-values.yaml)
    - [Admintools values](https://charts.nected.io/values/admintools-values.yaml)
    - [Temporal values](https://charts.nected.io/values/temporal-values.yaml)
    - [Nected Services values](https://charts.nected.io/values/nected-services-values.yaml)

3. Update following values in "values/*.yaml" files, adjust Ingress annotations based on ingressClass, and consider switching domains to https in case going to use SSL certificates.
    - `<<LicenseKey>>`
    - `<<frontend-konark-domain>>`
    - `<<frontend-editor-domain>>`
    - `<<backend-nalanda-domain>>`
    - `<<backend-vidhaan-router-domain>>`
    - `<<MongoPassword>>`
    - `<<PostgresUserName>>`
    - `<<PostgresPassword>>`
    - `<<ElasticUserPass>>`
    - `<<ingressClassName>>`
    - `<<pathType>>`
    - `<<DefaultUser>>`
    - `<<DefaultPassword>>`
    - `<<senderEmail>>`
    - `<<SendeName>>`
    - `<<emailHostName>>`
    - `<<senderUsername>>`
    - `<<senderPassword>>`
    - `<<ingressClassName>>`

4. When installing databases with nected's chart, include datastore in the installation.
   ```
   helm install datastore nected/datastore -f values/datastore-values.yaml
   ```

5. After deploying datastore, install Temporal's admin tools and initialize its schema.
    ```
    helm install admintools nected/temporal -f values/admintools-values.yaml

    kubctl get pods
    kubectl exec -it admintools-temporal-admintools-xxxxxxx-xxxx -- /bin/bash

    export SQL_PLUGIN=postgres
    export SQL_HOST=datastore-postgresql
    export SQL_PORT=5432
    export SQL_USER=<<PostgresUserName>>
    export SQL_PASSWORD=<<PostgresUserName>>

    temporal-sql-tool --db temporal create-database
    SQL_DATABASE=temporal temporal-sql-tool setup-schema -v 0.0
    SQL_DATABASE=temporal temporal-sql-tool update -schema-dir schema/postgresql/v96/temporal/versioned

    temporal-sql-tool --db temporal_visibility create-database
    SQL_DATABASE=temporal_visibility temporal-sql-tool setup-schema -v 0.0
    SQL_DATABASE=temporal_visibility temporal-sql-tool update -schema-dir schema/postgresql/v96/visibility/versioned
    ```

6. Now install temporal:
    ```
    helm install temporal nected/temporal -f values/temporal-values.yaml
    ```

7. Install Nected services:
    ```
    helm install nected nected/nected -f values/nected-services-values.yaml
    ```

With all services running, access the application through the fronend-konark domain using the default username and password.
