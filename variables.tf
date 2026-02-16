variable "cluster_name" {
  description = "Name of the existing EKS cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to deploy PgDog into"
  type        = string
  default     = "default"
}

variable "create_namespace" {
  description = "Whether to create the namespace if it doesn't exist"
  type        = bool
  default     = false
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "pgdog"
}

variable "chart_version" {
  description = "PgDog Helm chart version"
  type        = string
  default     = null
}

variable "chart_repository" {
  description = "Helm chart repository URL"
  type        = string
  default     = "https://helm.pgdog.dev"
}

variable "rds_instances" {
  description = "RDS instances to configure as databases. database_name is the PgDog logical name and must match users.database."
  type = list(object({
    identifier    = string
    database_name = string
    pool_size     = optional(number)
    shard         = optional(number, 0)
  }))
  default = []
}

variable "aurora_clusters" {
  description = "Aurora clusters to configure as databases. database_name is the PgDog logical name and must match users.database."
  type = list(object({
    cluster_identifier = string
    database_name      = string
    pool_size          = optional(number)
    shard              = optional(number, 0)
  }))
  default = []
}

variable "databases" {
  description = "Direct database configuration (alternative to rds_instances/aurora_clusters)"
  type = list(object({
    name      = string
    host      = string
    port      = optional(number, 5432)
    pool_size = optional(number)
    role      = optional(string, "primary")
    shard     = optional(number, 0)
  }))
  default = []
}

variable "users" {
  description = "PgDog users. Password is fetched as plaintext from AWS Secrets Manager using secret_arn."
  type = list(object({
    name                       = string
    database                   = string
    secret_arn                 = string
    pool_size                  = optional(number)
    min_pool_size              = optional(number)
    pooler_mode                = optional(string)
    server_user                = optional(string)
    server_password_secret_arn = optional(string)
  }))
  default   = []
  sensitive = true
}

variable "external_secrets" {
  description = <<-EOT
    Configure External Secrets Operator to pull users.toml from a secret store.
    Mutually exclusive with the users variable — when enabled, the users variable is ignored
    and passwords are managed entirely outside of Terraform.
  EOT
  type = object({
    secret_store_name = string
    secret_store_kind = optional(string, "SecretStore")
    refresh_interval  = optional(string, "1h")
    remote_refs = list(object({
      secret_key = string
      remote_ref = object({
        key      = string
        property = optional(string)
      })
    }))
  })
  default = null
}

variable "helm_values" {
  description = "Additional Helm values to merge (databases are auto-populated)"
  type        = any
  default     = {}
}
