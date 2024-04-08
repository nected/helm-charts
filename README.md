# Pre-Requisite
1. Create a load balance, in case of Azure need to create application gateway 
  for Azure: https://learn.microsoft.com/en-us/azure/application-gateway/tutorial-ingress-controller-add-on-existing
https://learn.microsoft.com/en-us/azure/application-gateway/ingress-controller-install-existing


2. Map 4 domains to loadbalaner
  - <<frontend-konark-domain>>
  - <<frontend-editor-domain>>
  - <<backend-nalanda-domain>>
  - <<backend-vidhaan-router-domain>>

3. need to enable storage drivers, e.g: for azure execute:
    az aks update -n <Cluster Name> -g <Resource Group> --enable-disk-driver --enable-file-driver --enable-blob-driver --enable-snapshot-controller

# Deployment steps
1. update values all values files (values/*.yaml):
  - <<LicenseKey>>
  - <<frontend-konark-domain>>
  - <<frontend-editor-domain>>
  - <<backend-nalanda-domain>>
  - <<backend-vidhaan-router-domain>>
  - <<MongoPassword>>
  - <<PostgresUserName>>
  - <<PostgresPassword>>
  - <<ElasticUserPass>>
  - <<ingressClassName>>
  - <<pathType>>
  - <<DefaultUser>>
  - <<DefaultPassword>>
  - <<senderEmail>>
  - <<SendeName>>
  - <<emailHostName>>
  - <<senderUsername>>
  - <<senderPassword>>


2. Install helm of datastore in case internal datastore required.
    - helm install datastore charts/nected/datastore -f values/datastore-values.yaml

3. once datastore is deployed then deploye Nalanda, konark, editor, sql-linter:
    helm install nalanda charts/nalanda/ -f values/nalanda-values.yaml
    helm install sql-linter charts/sql-linter/
    helm install konark charts/konark/ -f values/konark-values.yaml
    helm install editor charts/nected-editor/ -f values/editor-values.yaml

4. Install Temporal
    - update temporal-values.yaml 
      - set server: enabled false
      - set admin-tools: enabled true
    - helm install temporal charts/temporal/ -f values/temporal-values.yaml
    - kubctl get pods 
    - go inside admintools pod
    -   kubectl exec -it nected-temporal-admintools-xxxxxxx-xxxx -- /bin/bash
    - execute:
      export SQL_PLUGIN=postgres
      export SQL_HOST=datastore-postgresql
      export SQL_PORT=5432
      export SQL_USER=nected
      export SQL_PASSWORD=NecTedPsql1234

      #make temporal-sql-tool

      temporal-sql-tool --db temporal create-database 
      SQL_DATABASE=temporal temporal-sql-tool setup-schema -v 0.0
      SQL_DATABASE=temporal temporal-sql-tool update -schema-dir schema/postgresql/v96/temporal/versioned

      temporal-sql-tool --db temporal_visibility create-database
      SQL_DATABASE=temporal_visibility temporal-sql-tool setup-schema -v 0.0
      SQL_DATABASE=temporal_visibility temporal-sql-tool update -schema-dir schema/postgresql/v96/visibility/versioned

    - update temporal-values.yaml 
      - set server: enabled true
      - set admin-tools: enabled false
      
    - helm upgrade temporal charts/temporal/ -f values/temporal-values.yaml

5. Install Vidhaan services
    helm install router charts/vidhaan-router/ -f values/vidhaan-router-values.yaml
    helm install executer charts/vidhaan-executer/ -f values/vidhaan-executer-values.yaml

6. Access http://<<frontend-konark-domain>>, signin using  <<DefaultUser>> & <<DefaultPassword>>
