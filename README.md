# Nected OnPremise
Installation using Helm charts

![Nected Onpremise Architecture](https://assets.nected.io/nalanda/nected-onpremise-arch.jpg)

## Pre-Requisite
1. A loadbalance with public subnet
2. Map 4 domains to loadbalaner
  - `<<frontend-konark-domain>>`
  - `<<frontend-editor-domain>>`
  - `<<backend-nalanda-domain>>`
  - `<<backend-vidhaan-router-domain>>`
3. need to enable storage drivers, e.g: azure execute:
   ```
   az aks update -n <Cluster Name> -g <Resource Group> --enable-disk-driver --enable-file-driver --enable-blob-driver --enable-snapshot-controller
   ```

## Deployment steps
1. The following values need to be updated in the "values/*.yaml" files:
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

  Also update ingress annotations accordingly.

2. If using nected provided chart to install databases, install datastore:
   ```
   helm install datastore charts/datastore/ -f values/datastore-values.yaml
   ```

3. Once datastore is deployed, Install Temporal's admintools & create schema:
    ```
    helm install admintools charts/temporal/ -f values/admintools-values.yaml

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

4. Now install temporal:
    ```
    helm install temporal charts/temporal/ -f values/temporal-values.yaml
    ```

4. Install Nected services:
    ```
    helm install nected charts/nected-services/ -f values/nected-services-values.yaml
    ```

Once all services are up, access using fronend-konark domain and defaul username / password.
