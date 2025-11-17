# 🚀 Nected OnPremise Installation (via Helm Charts)

![Nected OnPremise Architecture](https://assets.nected.ai/nalanda/Nected-Tech-Architecture.jpg)

This guide walks you through deploying **Nected** on your own Kubernetes cluster using Helm charts.

---

## ✅ Pre-Requisites

1. **Application Load Balancer**
2. **Domain Setup & Ingress Configuration**

You’ll need **three fully qualified domain names (FQDNs)** pointing to your cluster’s ingress controller:

| Service                  | Values Placeholder     | Example Domain     |
|--------------------------|------------------------|--------------------|
| `nected-konark`          | `<<ui-domain>>`        | `app.xyz.com`      |
| `nected-nalanda`         | `<<backend-domain>>`   | `api.xyz.com`      |
| `nected-vidhaan-router`  | `<<router-domain>>`    | `router.xyz.com`   |

> 💡 **Ingress Setup:**
- Create `ingress.yaml` for reference download sample file.
- [Ingress config](https://charts.nected.io/values/azure-ingress-sample.yaml)
- Setup ingress, once all services are deployed:
```
kubectl apply -f ingress.yaml
```

### 📌 Update DNS
Point each domain to your ingress controller’s external IP:

- `app.xyz.com` → `<Ingress External IP>`
- `api.xyz.com` → `<Ingress External IP>`
- `router.xyz.com` → `<Ingress External IP>`

3. **PostgreSQL** - With DB/table creation privileges
4. **Redis** - Endpoint and credentials
5. **Elasticsearch / OpenSearch (Optional)**

> 💡 **For Dev Environments:**
Use Nected’s datastore chart if you don’t have PostgreSQL, Redis, or Elasticsearch installed:
- [Datastore values](https://charts.nected.io/values/datastore-values.yaml)
- Install chart
```
helm upgrade -i datastore nected/datastore -f datastore-values.yaml
```

## 🛠️ Installation Steps
### 📦 Add Helm Repo
```
helm repo add nected https://nected.github.io/helm-charts
```

### 📄 Download Sample Values Files
- [Temporal values](https://charts.nected.io/values/temporal-values.yaml)
- [Nected values](https://charts.nected.io/values/nected-values.yaml)

### 🌐 Configure Scheme and Domains
In `nected-values.yaml`, replace the following placeholders:

| Values Placeholder   | Replace With       |
|----------------------|--------------------|
| `<<scheme>>`         | `http` or `https`  |
| `<<ui-domain>>`      | `app.xyz.com`      |
| `<<backend-domain>>` | `api.xyz.com`      |
| `<<router-domain>>`  | `router.xyz.com`   |


### 🔐 Configure default user credentials
In `nected-values.yaml`:
```
NECTED_UI_USER_NAME: &uiUserName dev@nected.ai
NECTED_UI_USER_PASSWORD: &uiUserPassword devPass123
```

### 🗄️ Configure PostgreSQL
1. In `temporal-values.yaml`:
```
NECTED_PG_HOST: &pgHost datastore-postgresql
NECTED_PG_USER: &pgUser nected
NECTED_PG_PASSWORD: &pgPassword psqlPass123
NECTED_PG_PORT: &pgPort 5432
NECTED_PG_TLS_ENABLED: &pgTlsEnabled false
NECTED_PG_HOST_VERIFICATIO: &pgHostVerification false
```
2. In `nected-values.yaml`:
```
NECTED_PG_HOST: &pgHost datastore-postgresql
NECTED_PG_DATABASE: &pgDatabase nected
NECTED_PG_USER: &pgUser nected
NECTED_PG_PASSWORD: &pgPassword psqlPass123
NECTED_PG_PORT: &pgPort "5432"
NECTED_PG_SSL_MODE: &pgSslMode disable
```

#### Azure PostgreSQL Flexible Server
1. Go to the Azure Portal, Navigate to your PostgreSQL Flexible Server instance.
2. Open "Server Parameters", In the left-side menu under Settings, click "Server Parameters".
3. Find the azure.extensions parameter, Search for azure.extensions using the search bar.
4. Add btree_gin to the list, If btree_gin is not already listed, append it to the existing list. 
Example: hstore,pg_trgm,btree_gin
5. Click Save, This change will not restart the server—it takes effect immediately. Create the Extension in Your Database.
6. After enabling it in parameters:
```
CREATE EXTENSION IF NOT EXISTS btree_gin;
```
**Notes**: No changes required if using the Nected-provided datastore.

### 🧠 Configure Redis
In `nected-values.yaml`:
```
NECTED_REDIS_TLS_ENABLED: &redisTlsEnabled "false"
NECTED_REDIS_INSECURE_TLS: &redisInsecureTls "true"
NECTED_REDIS_HOST_PORT: &redisHostPort datastore-redis-master:6379
NECTED_REDIS_HOST: &redisHost datastore-redis-master
NECTED_REDIS_PORT: &redisPort "6379"
NECTED_REDIS_USERNAME: &redisUser ""
NECTED_REDIS_PASSWORD: &redisPassword ""
```
**Notes**: No changes required if using the Nected-provided datastore.

### 🔍 Configure Elasticsearch / OpenSearch
In `nected-values.yaml`:
```
NECTED_ELASTIC_ENABLED: &elasticEnabled "true"
# possible values: managed / opensearch
NECTED_ELASTIC_PROVIDER: &elasticProvider managed
NECTED_ELASTIC_HOSTS: &elasticHost http://elasticsearch-master:9200
NECTED_ELASTIC_INSECURE_TLS: &elasticInsecureTls "true"
NECTED_ELASTIC_API_KEY: &elasticAPiKey ""
NECTED_ELASTIC_USER: &elasticUser elastic
NECTED_ELASTIC_PASSWORD: &elasticPassword esPass123
```

**Optional**: To disable audit logging:
```
NECTED_ELASTIC_ENABLED: &elasticEnabled "false"
```
**Notes**: No changes required if using the Nected-provided datastore.

### 🔐 Enable Credential Encryption at Rest
1. Generate a private key and create a Kubernetes secret:
 ```
openssl genrsa -f4 -out encryption-at-rest 4096
kubectl create secret generic encryption-at-rest-secret --from-file encryption-at-rest
```
2. In `nected-values.yaml`, uncomment the `existingSecretMap` block to use the secret.

### 🚀 Install Nected Services
1. Install **Temporal**:
    ```
    helm upgrade -i temporal nected/temporal -f values/temporal-values.yaml
    ```
2. Install **Nected**:
    ```
    helm upgrade -i nected nected/nected -f values/nected-values.yaml
    ```

### ✅ Access the Application
Visit the application via your configured `<<ui-domain>>`.
Login using default credentials defined in `nected-values.yaml`:
```
NECTED_USER_EMAIL: dev@nected.ai
NECTED_USER_PASSWORD: devPass123
```

---
## 🤝 Community & Support
For questions, feedback, or contributions:
- Visit our [documentation](https://docs.nected.ai/)
- Join the conversation on [LinkedIn](https://www.linkedin.com/company/nected-ai/)
- Contact the team via support@nected.ai