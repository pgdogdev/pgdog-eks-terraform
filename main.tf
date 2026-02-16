data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

# Look up each RDS instance
data "aws_db_instance" "rds" {
  for_each               = { for db in var.rds_instances : db.identifier => db }
  db_instance_identifier = each.key
}

# Fetch user password secrets from AWS Secrets Manager (skipped when using external_secrets)
locals {
  use_external_secrets = var.external_secrets != null
  all_secret_arns = local.use_external_secrets ? toset([]) : toset(compact(concat(
    [for u in var.users : u.secret_arn],
    [for u in var.users : u.server_password_secret_arn if u.server_password_secret_arn != null],
  )))
}

data "aws_secretsmanager_secret_version" "user" {
  for_each  = local.all_secret_arns
  secret_id = each.value
}

# Look up each Aurora cluster to discover its member instances
data "aws_rds_cluster" "aurora" {
  for_each           = { for c in var.aurora_clusters : c.cluster_identifier => c }
  cluster_identifier = each.key
}

locals {
  has_aurora = length(var.aurora_clusters) > 0

  # Map Aurora instance id → cluster config (needed for data source for_each)
  aurora_instance_configs = merge([
    for cluster in var.aurora_clusters : {
      for member in data.aws_rds_cluster.aurora[cluster.cluster_identifier].cluster_members :
      member => {
        database_name = cluster.database_name
        pool_size     = cluster.pool_size
        shard         = cluster.shard
      }
    }
  ]...)
}

# Look up each Aurora cluster member instance for its individual endpoint
data "aws_db_instance" "aurora_instance" {
  for_each               = local.aurora_instance_configs
  db_instance_identifier = each.key
}

locals {
  # RDS instances → one entry per instance, role detected from replica status
  rds_databases = [
    for db in var.rds_instances : merge(
      {
        name = db.database_name
        host = data.aws_db_instance.rds[db.identifier].address
        port = data.aws_db_instance.rds[db.identifier].port
      },
      db.pool_size != null ? { poolSize = db.pool_size } : {},
      db.shard != 0 ? { shard = db.shard } : {},
      data.aws_db_instance.rds[db.identifier].replicate_source_db != "" ? { role = "replica" } : { role = "primary" },
    )
  ]

  # Aurora instances → one entry per instance, all with role "auto"
  aurora_databases = [
    for id, inst in data.aws_db_instance.aurora_instance : merge(
      {
        name = local.aurora_instance_configs[id].database_name
        host = inst.address
        port = inst.port
        role = "auto"
      },
      local.aurora_instance_configs[id].pool_size != null ? { poolSize = local.aurora_instance_configs[id].pool_size } : {},
      local.aurora_instance_configs[id].shard != 0 ? { shard = local.aurora_instance_configs[id].shard } : {},
    )
  ]

  # Direct database entries
  direct_databases = [
    for db in var.databases : merge(
      {
        name = db.name
        host = db.host
        port = db.port
        role = db.role
      },
      db.pool_size != null ? { poolSize = db.pool_size } : {},
      db.shard != 0 ? { shard = db.shard } : {},
    )
  ]

  all_databases = concat(local.rds_databases, local.aurora_databases, local.direct_databases)

  users = local.use_external_secrets ? [] : [
    for u in var.users : merge(
      {
        name     = u.name
        database = u.database
        password = data.aws_secretsmanager_secret_version.user[u.secret_arn].secret_string
      },
      u.pool_size != null ? { poolSize = u.pool_size } : {},
      u.min_pool_size != null ? { minPoolSize = u.min_pool_size } : {},
      u.pooler_mode != null ? { poolerMode = u.pooler_mode } : {},
      u.server_user != null ? { serverUser = u.server_user } : {},
      u.server_password_secret_arn != null ? {
        serverPassword = data.aws_secretsmanager_secret_version.user[u.server_password_secret_arn].secret_string
      } : {},
    )
  ]

  external_secrets_values = local.use_external_secrets ? {
    externalSecrets = {
      enabled         = true
      create          = true
      refreshInterval = var.external_secrets.refresh_interval
      secretStoreRef = {
        name = var.external_secrets.secret_store_name
        kind = var.external_secrets.secret_store_kind
      }
      remoteRefs = var.external_secrets.remote_refs
    }
  } : {}

  computed_values = merge(
    var.helm_values,
    {
      databases = local.all_databases
    },
    length(local.users) > 0 ? { users = local.users } : {},
    local.external_secrets_values,
    local.has_aurora ? {
      lsnCheckDelay    = 0
      lsnCheckInterval = 1000
    } : {},
  )
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

resource "helm_release" "pgdog" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = var.create_namespace

  repository = var.chart_repository
  chart      = "pgdog"
  version    = var.chart_version

  values = [yamlencode(local.computed_values)]
}
