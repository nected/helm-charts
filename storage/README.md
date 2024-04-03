


az aks update -n nected-dev -g Nected-RG --enable-disk-driver --enable-file-driver --enable-blob-driver --enable-snapshot-controller

az aks update -n nected-dev -g Nected-RG --disable-disk-driver --disable-file-driver --disable-blob-driver --disable-snapshot-controller
