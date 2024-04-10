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
1. Update values in all values files (values/*.yaml):
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


2. Install helm of datastore in case internal datastore required.
   ```
   helm install datastore charts/nected/datastore -f values/datastore-values.yaml
   ```

5. Once datastore is deployed, Install Temporal
    - update temporal-values.yaml
      - set `server: enabled: false`
      - set `admin-tools: enabled: true`
   -  install Temporal chart
     ```
      helm install temporal charts/temporal/ -f values/temporal-values.yaml
     ```
    - go inside admintools pod
      ```
      kubctl get pods
      kubectl exec -it nected-temporal-admintools-xxxxxxx-xxxx -- /bin/bash
      ```
      - set db environment inside admintools pod:
        ```export SQL_PLUGIN=postgres
        export SQL_HOST=datastore-postgresql
        export SQL_PORT=5432
        export SQL_USER=<<PostgresUserName>>
        export SQL_PASSWORD=<<PostgresUserName>>```
  
      - set up temporal schema:
        ```temporal-sql-tool --db temporal create-database 
        SQL_DATABASE=temporal temporal-sql-tool setup-schema -v 0.0
        SQL_DATABASE=temporal temporal-sql-tool update -schema-dir schema/postgresql/v96/temporal/versioned
  
        temporal-sql-tool --db temporal_visibility create-database
        SQL_DATABASE=temporal_visibility temporal-sql-tool setup-schema -v 0.0
        SQL_DATABASE=temporal_visibility temporal-sql-tool update -schema-dir schema/postgresql/v96/visibility/versioned```

    - revert previous changes temporal-values.yaml 
      - set `server: enabled: true`
      - set `admin-tools: enabled: false`
      
      -  install Temporal chart
        ```
        helm upgrade temporal charts/temporal/ -f values/temporal-values.yaml
        ````

6. Install Nected services
    ```
    helm install nalanda charts/nalanda/ -f values/nalanda-values.yaml
    helm install sql-linter charts/sql-linter/
    helm install konark charts/konark/ -f values/konark-values.yaml
    helm install editor charts/nected-editor/ -f values/editor-values.yaml
    helm install vidhaan-router charts/vidhaan-router/ -f values/vidhaan-router-values.yaml
    helm install vidhaan-executer charts/vidhaan-executer/ -f values/vidhaan-executer-values.yaml
    ```

7. Access  Nected services:
   ```
   http://<<frontend-konark-domain>>, signin using  <<DefaultUser>> & <<DefaultPassword>>
   ```
