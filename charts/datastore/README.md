PreRequisite:
# Install storage CSI Driver for Azure
  az aks update -n <Cluster Name> -g <Resource Group> --enable-disk-driver --enable-file-driver --enable-blob-driver --enable-snapshot-controller

# Install 


helm depedency build
helm install datastore ./
