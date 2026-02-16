# PgDog EKS Terraform Module

Deploys [PgDog](https://pgdog.dev) to an existing AWS EKS cluster via Helm. Auto-discovers RDS and Aurora databases and configures them in the Helm chart.

## Usage

```hcl
module "pgdog" {
  source = "github.com/pgdogdev/pgdog-eks-terraform"

  cluster_name = "my-eks-cluster"
  namespace    = "pgdog"

  aurora_clusters = [
    {
      cluster_identifier = "my-aurora-cluster"
      database_name      = "mydb"
    },
  ]

  users = [
    {
      name       = "myapp"
      database   = "mydb" # must match database_name above
      secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:pgdog/myapp-AbCdEf"
    },
  ]
}
```

## Database Discovery

The `database_name` field on `rds_instances`, `aurora_clusters`, and `databases` is the PgDog logical database name. It must match the `database` field on `users` entries to connect users to databases.

### RDS Instances

Each RDS instance is looked up via `aws_db_instance`. The module detects the role automatically:

- Standalone instances get `role = "primary"`
- Read replicas (where `replicate_source_db` is set) get `role = "replica"`

```hcl
rds_instances = [
  {
    identifier    = "my-postgres-primary"
    database_name = "mydb"
  },
  {
    identifier    = "my-postgres-replica"
    database_name = "mydb"
  },
]
```

### Aurora Clusters

Each Aurora cluster is looked up via `aws_rds_cluster` to discover its `cluster_members`. Each member instance is resolved individually via `aws_db_instance` to get its direct endpoint (cluster-level read/write endpoints are not used).

All Aurora instances get `role = "auto"` so PgDog detects primary/replica via LSN monitoring. When Aurora clusters are present, the module automatically sets `lsnCheckDelay = 0` and `lsnCheckInterval = 1000`.

```hcl
aurora_clusters = [
  {
    cluster_identifier = "my-aurora-cluster"
    database_name      = "mydb"
  },
]
```

## User Passwords

Two mutually exclusive approaches are supported.

### Option A: Terraform-managed (via `users`)

Passwords are fetched from AWS Secrets Manager at plan/apply time and passed to the Helm chart as values. Each secret should contain the password as plaintext.

**Note:** Passwords will be stored in Terraform state.

```hcl
users = [
  {
    name       = "myapp"
    database   = "mydb"
    secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:myapp-password"
  },
]
```

### Option B: External Secrets Operator (via `external_secrets`)

The [External Secrets Operator](https://external-secrets.io/) pulls `users.toml` directly from a secret store in-cluster. Passwords never enter Terraform state. Requires a `SecretStore` resource to already exist in the namespace.

```hcl
external_secrets = {
  secret_store_name = "aws-secrets-manager"
  remote_refs = [
    {
      secret_key = "users.toml"
      remote_ref = {
        key = "pgdog/production/users"
      }
    },
  ]
}
```

## Variables

### Required

| Name | Type | Description |
|------|------|-------------|
| `cluster_name` | `string` | Name of the existing EKS cluster |

### Helm Chart

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `release_name` | `string` | `"pgdog"` | Helm release name |
| `namespace` | `string` | `"default"` | Kubernetes namespace to deploy into |
| `create_namespace` | `bool` | `false` | Whether to create the namespace if it doesn't exist |
| `chart_version` | `string` | `null` | PgDog Helm chart version (latest if unset) |
| `chart_repository` | `string` | `"https://helm.pgdog.dev"` | Helm chart repository URL |
| `helm_values` | `any` | `{}` | Additional Helm values to merge (databases and users are auto-populated) |

### Database Discovery

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `rds_instances` | `list(object)` | `[]` | RDS instances to configure as databases |
| `aurora_clusters` | `list(object)` | `[]` | Aurora clusters to configure as databases |
| `databases` | `list(object)` | `[]` | Direct database entries (alternative to auto-discovery) |

#### `rds_instances` entries

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `identifier` | `string` | yes | | RDS instance identifier |
| `database_name` | `string` | yes | | PgDog logical database name (must match `users.database`) |
| `pool_size` | `number` | no | | Pool size |
| `shard` | `number` | no | `0` | Shard number |

#### `aurora_clusters` entries

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `cluster_identifier` | `string` | yes | | Aurora cluster identifier |
| `database_name` | `string` | yes | | PgDog logical database name (must match `users.database`) |
| `pool_size` | `number` | no | | Pool size |
| `shard` | `number` | no | `0` | Shard number |

#### `databases` entries

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | `string` | yes | | PgDog logical database name (must match `users.database`) |
| `host` | `string` | yes | | Database host |
| `port` | `number` | no | `5432` | Port |
| `pool_size` | `number` | no | | Pool size |
| `role` | `string` | no | `"primary"` | Role (`"primary"`, `"replica"`, `"auto"`) |
| `shard` | `number` | no | `0` | Shard number |

### Users

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `users` | `list(object)` | `[]` | Users with passwords from Secrets Manager (sensitive) |
| `external_secrets` | `object` | `null` | External Secrets Operator config (mutually exclusive with `users`) |

#### `users` entries

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | `string` | yes | Username |
| `database` | `string` | yes | Database name (must match a `database_name` from databases) |
| `secret_arn` | `string` | yes | Secrets Manager ARN containing the plaintext password |
| `pool_size` | `number` | no | Pool size |
| `min_pool_size` | `number` | no | Minimum pool size |
| `pooler_mode` | `string` | no | Pooler mode |
| `server_user` | `string` | no | Server-side username |
| `server_password_secret_arn` | `string` | no | Secrets Manager ARN for the server-side password |

#### `external_secrets`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `secret_store_name` | `string` | required | Name of the SecretStore resource |
| `secret_store_kind` | `string` | `"SecretStore"` | Kind (`"SecretStore"` or `"ClusterSecretStore"`) |
| `refresh_interval` | `string` | `"1h"` | How often to sync secrets |
| `remote_refs` | `list(object)` | required | Secret key / remote ref mappings |

Each `remote_refs` entry:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `secret_key` | `string` | yes | Key in the K8s Secret (e.g. `"users.toml"`) |
| `remote_ref.key` | `string` | yes | Key in the external secret store |
| `remote_ref.property` | `string` | no | Specific property within the secret |

## Outputs

| Name | Description |
|------|-------------|
| `release_name` | Helm release name |
| `namespace` | Kubernetes namespace |
| `chart_version` | Deployed chart version |
| `databases` | List of database entries passed to the Helm chart |

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.3 |
| AWS provider | >= 5.0 |
| Helm provider | >= 2.9 |
