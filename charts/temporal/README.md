helm delete temporal

helm upgrade -i temporal ./ -f values.yaml -f values/values.dynamic_config.yaml -f values/values.elasticsearch.yaml -f values/values.ndc.yaml -f values/values.postgresql.yaml -f values/values.resources.yaml  --timeout 15m