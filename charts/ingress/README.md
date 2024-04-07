Refrence Doc = https://learn.microsoft.com/en-us/azure/application-gateway/tutorial-ingress-controller-add-on-existing
https://learn.microsoft.com/en-us/azure/application-gateway/ingress-controller-install-existing


az account set --subscription <<SubcriptionID>>
az group create --name Nected-RG --location centralindia
az aks get-credentials --resource-group Nected-RG --name nected-dev --overwrite-existing

az aks update -n nected-dev -g Nected-RG --enable-disk-driver --enable-file-driver --enable-blob-driver --enable-snapshot-controller

az network public-ip create -n <<PublicIPname>> -g Nected-RG --allocation-method Static --sku Standard

az network vnet create -n myVnet -g Nected-RG --address-prefix 10.0.0.0/16 --subnet-name mySubnet --subnet-prefix 10.0.0.0/24 

az network application-gateway create -n myApplicationGateway -g Nected-RG --sku Standard_v2 --public-ip-address <<PublicIPname>> --vnet-name myVnet --subnet mySubnet --priority 100

# Enable Addon
az aks enable-addons -n nected-dev -g Nected-RG -a ingress-appgw --appgw-id <<ApplicationGatewayID>>

If Application gateway and AKS nodes Virtual network are different then peering required.

aksVnetId=$(az network vnet show -n <aks-vnet-Name> -g MC_Nected-RG_nected-dev_centralindia -o tsv --query "id")
az network vnet peering create -n AppGWtoAKSVnetPeering -g Nected-RG --vnet-name <aks-vnet-Name> --remote-vnet $aksVnetId --allow-vnet-access

appGWVnetId=$(az network vnet show -n <aks-vnet-Name> -g Nected-RG -o tsv --query "id")
az network vnet peering create -n AKStoAppGWVnetPeering -g MC_Nected-RG_nected-dev_centralindia --vnet-name <aks-vnet-Name> --remote-vnet $appGWVnetId --allow-vnet-access


# Identity
az identity create --name "nected-gw-id" --resource-group "Nected-RG" --location "centralindia" --subscription "<<SubscriptionID>>"

az identity list -g Nected-RG --query "[?name == 'nected-gw-id'].principalId | [0]" -o tsv

export resourceGroup="Nected-RG"
export identityName="nected-gw-id"
export appGatewayID=$(az network application-gateway list --query '[].id' -o tsv)
export principalId=$(az identity list -g $resourceGroup --query "[?name == '$identityName'].principalId | [0]" -o tsv)


az role assignment create --assignee $principalId --role contributor --scope $appGatewayID

export AppGatewayResourceGroup=$(az network application-gateway list --query '[].resourceGroup' -o tsv)
export AppGatewayResourceGroupID=$(az group show --name $AppGatewayResourceGroup --query id -o tsv)

az role assignment create --role Reader --assignee $principalId  --scope $AppGatewayResourceGroupID

# Identity Required "Network Contributor" role assiged manually.

# Helm Chart
helm repo add application-gateway-kubernetes-ingress https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/
helm repo update

# Update helm-config.yaml 
helm install --name ingress-azure -f helm-config.yaml application-gateway-kubernetes-ingress/ingress-azure

###
az aks update -n nected-dev -g Nected-RG --enable-oidc-issuer --enable-workload-identity

export AKS_OIDC_ISSUER="$(az aks show -n nected-dev -g Nected-RG --query "oidcIssuerProfile.issuerUrl" -o tsv)"

# Once helm run successfully There will be a service account created.

kubectl get sa -n <namespace>


az identity federated-credential create --name fedrated-access-gw-identity --identity-name nected-gw-id --resource-group Nected-RG --issuer "${AKS_OIDC_ISSUER}" --subject system:serviceaccount:default:ingress-azure --audience api://AzureADTokenExchange


Grant permissions to the service account

kubectl apply -f clusterrole.yaml