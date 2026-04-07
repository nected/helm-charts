# 🚀 Nected OnPremise Installation (via Helm Charts)

<img src="https://assets.nected.ai/nalanda/Nected-Tech-Architecture-v1.png" width="760" />

This guide walks you through deploying **Nected** on your own Kubernetes cluster using Helm charts.

---

## ✅ Pre-Requisites

### Domain Setup & Ingress Configuration

You’ll need **three fully qualified domain names (FQDNs)** pointing to your cluster’s ingress controller:

| Service                  | Values Placeholder     | Example Domain     |
|--------------------------|------------------------|--------------------|
| `nected-konark`          | `<<ui-domain>>`        | `app.xyz.com`      |
| `nected-nalanda`         | `<<backend-domain>>`   | `api.xyz.com`      |
| `nected-vidhaan-router`  | `<<router-domain>>`    | `router.xyz.com`   |

### Required Services

| Service        | Requirement                         |
|----------------|-------------------------------------|
| PostgreSQL     | Database with create/read/write.    |
| Redis          | Endpoint and authentication details |
| Elasticsearch  | Endpoint and authentication details |

#### 📌 PostgreSQL Notes
- Nected services expect the **`nected` database to be pre-created**.
- The configured user must have:
  - Database connection privileges
  - Permission to create tables, indexes, and extensions
- Ensure network access is allowed from the Kubernetes cluster.

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

#### 📌 ElasticSearch Notes
Ensure the configured user or API key has the following **cluster** and **index-level privileges**:
```json
{
    "read-write-role": {
        "cluster": [
            "monitor",
            "manage_ingest_pipelines",
            "manage_transform",
            "manage_ilm",
            "manage_index_templates"
        ],
        "indices": [{
            "names": ["*"],
            "privileges": [
                "read",
                "write",
                "create_index",
                "manage",
                "view_index_metadata",
                "manage_ilm",
                "monitor"
            ]
        }]
    }
}
```

> 💡 **For Dev Environments shortcut:**
Use Nected’s datastore chart if you don’t have PostgreSQL, Redis, or Elasticsearch installed:
- [Datastore values](https://charts.nected.io/values/datastore-values.yaml)
- Install chart
```
helm upgrade -i datastore nected/datastore -f datastore-values.yaml
```

## 🌐 Ingress Setup
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

---

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

## ⚙️ Scaling & Secrets

### Autoscaling

Default:

* Replica: 1
* Autoscaling: Disabled

Enable:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 4
```

### Secrets

#### Default

Uses ConfigMap:

* REDIS_PASSWORD
* ELASTIC_PASSWORD
* ELASTIC_API_KEY
* DB_PASSWORD
* MASTER_DB_PASSWORD

#### Recommended (Kubernetes Secret)

```bash
kubectl create secret generic nected-credential \
  --from-literal=MASTER_DB_PASSWORD=psqlPass123 \
  --from-literal=ELASTIC_PASSWORD=esPass123 \
  --from-literal=DB_PASSWORD=psqlPass123 \
  --from-literal=REDIS_PASSWORD=redisPass123 \
  --from-literal=ELASTIC_API_KEY=your-api-key
```

Update `nected-values.yaml`:

```yaml
existingSecret: nected-credential
```

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