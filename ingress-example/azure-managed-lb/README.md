Refrence Doc = https://learn.microsoft.com/en-us/azure/application-gateway/tutorial-ingress-controller-add-on-existing
https://learn.microsoft.com/en-us/azure/application-gateway/ingress-controller-install-existing


az account set --subscription <<SubcriptionID>>
az group create --name <<ResourceGroup>> --location centralindia
az aks get-credentials --resource-group <<ResourceGroup>> --name <<nameSpace>> --overwrite-existing

az aks update -n <<nameSpace>> -g <<ResourceGroup>> --enable-disk-driver --enable-file-driver --enable-blob-driver --enable-snapshot-controller

az network public-ip create -n <<PublicIPname>> -g <<ResourceGroup>> --allocation-method Static --sku Standard

az network vnet create -n myVnet -g <<ResourceGroup>> --address-prefix 10.0.0.0/16 --subnet-name mySubnet --subnet-prefix 10.0.0.0/24 

az network application-gateway create -n <<applicationGatewayName>> -g <<ResourceGroup>> --sku Standard_v2 --public-ip-address <<PublicIPname>> --vnet-name myVnet --subnet mySubnet --priority 100

# Enable Addon
az aks enable-addons -n <<nameSpace>> -g <<ResourceGroup>> -a ingress-appgw --appgw-id <<ApplicationGatewayID>>

If Application gateway and AKS nodes Virtual network are different then peering required.

aksVnetId=$(az network vnet show -n <aks-vnet-Name> -g <<ClusterResourceGroup>-o tsv --query "id")
az network vnet peering create -n AppGWtoAKSVnetPeering -g <<ResourceGroup>> --vnet-name <aks-vnet-Name> --remote-vnet $aksVnetId --allow-vnet-access

appGWVnetId=$(az network vnet show -n <aks-vnet-Name> -g <<ResourceGroup>> -o tsv --query "id")
az network vnet peering create -n AKStoAppGWVnetPeering -g <<ClusterResourceGroup>>--vnet-name <aks-vnet-Name> --remote-vnet $appGWVnetId --allow-vnet-access


# Identity
az identity create --name "<<appGatewayId>>" --resource-group "<<ResourceGroup>>" --location "centralindia" --subscription "<<SubscriptionID>>"

az identity list -g <<ResourceGroup>> --query "[?name == '<<appGatewayId>>'].principalId | [0]" -o tsv

export resourceGroup="<<ResourceGroup>>"
export identityName="<<appGatewayId>>"
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
az aks update -n <<nameSpace>> -g <<ResourceGroup>> --enable-oidc-issuer --enable-workload-identity

export AKS_OIDC_ISSUER="$(az aks show -n <<nameSpace>> -g <<ResourceGroup>> --query "oidcIssuerProfile.issuerUrl" -o tsv)"

# Once helm run successfully There will be a service account created.

kubectl get sa -n <namespace>


az identity federated-credential create --name fedrated-access-gw-identity --identity-name <<appGatewayId>> --resource-group <<ResourceGroup>> --issuer "${AKS_OIDC_ISSUER}" --subject system:serviceaccount:default:ingress-azure --audience api://AzureADTokenExchange


Grant permissions to the service account

kubectl apply -f clusterrole.yaml