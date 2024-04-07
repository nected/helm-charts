change directory

cd temporal/temporal-dev

# Temporal Demo

helm delete temporal-dev -n temporal

# if storage is postgres then run first time with admin-ttol enabled only
# use admin-tool pod to create schema manually for postgre db temporal & temporal_visibility
export SQL_PLUGIN=postgres
export SQL_HOST=postgresql_host
export SQL_PORT=5432
export SQL_USER=postgresql_user
export SQL_PASSWORD=postgresql_password

#make temporal-sql-tool

temporal-sql-tool --tls --tls-disable-host-verification --db temporal create-database 
SQL_DATABASE=temporal temporal-sql-tool --tls --tls-disable-host-verification setup-schema -v 0.0
SQL_DATABASE=temporal temporal-sql-tool --tls --tls-disable-host-verification update -schema-dir schema/postgresql/v96/temporal/versioned

temporal-sql-tool --tls --tls-disable-host-verification --db temporal_visibility create-database
SQL_DATABASE=temporal_visibility temporal-sql-tool --tls --tls-disable-host-verification setup-schema -v 0.0
SQL_DATABASE=temporal_visibility temporal-sql-tool --tls --tls-disable-host-verification update -schema-dir schema/postgresql/v96/visibility/versioned

steps 1 : setup es index let PG index fail, helm install using setup true
steps 2 : delete jobs and pods and delete installation
steps 3 : install using server enable false, setup false
steps 4 : use admin tool pod to setup and update PG schema
steps 5 : helm upgrade after changing server enable true

# then enable server and web and run upgrade

helm install temporal-dev ./ -f values.yaml -f values/values.dynamic_config.yaml -f values/values.elasticsearch.yaml -f values/values.ndc.yaml -f values/values.postgresql.yaml -f values/values.resources.yaml -n temporal  --timeout 15m

helm upgrade temporal-dev ./ -f values.yaml -f values/values.dynamic_config.yaml -f values/values.elasticsearch.yaml -f values/values.ndc.yaml -f values/values.postgresql.yaml -f values/values.resources.yaml -n temporal  --timeout 15m

