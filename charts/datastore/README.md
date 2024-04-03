PreRequisite:
# Install storage CSI Driver for Azure
  az aks update -n <Cluster Name> -g <Resource Group> --enable-disk-driver --enable-file-driver --enable-blob-driver --enable-snapshot-controller

# Install 

helm repo add bitnami https://charts.bitnami.com/bitnami


helm install my-psql bitnami/postgresql --version 15.2.2 -f values/pg-values.yaml
helm install my-mongo bitnami/mongodb  --version 15.1.1 -f values/mongo-values.yaml
helm install my-redis bitnami/redis  --version 19.0.2 -f values/redis-values.yaml
helm install my-elatic elastic/elasticsearch  --version 8.5.1 -f values/es-values.yaml