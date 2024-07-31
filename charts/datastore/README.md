# Nected Datastore
helm charts to install data stores requred for Nected platform

PreRequisite:
# Install storage CSI Driver for Azure
  az aks update -n <Cluster Name> -g <Resource Group> --enable-disk-driver --enable-file-driver --enable-blob-driver --enable-snapshot-controller

# Install 


helm dependency build
helm install datastore ./
