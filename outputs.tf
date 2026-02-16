output "release_name" {
  description = "Helm release name"
  value       = helm_release.pgdog.name
}

output "namespace" {
  description = "Kubernetes namespace where PgDog is deployed"
  value       = helm_release.pgdog.namespace
}

output "databases" {
  description = "List of database entries passed to the Helm chart"
  value       = local.all_databases
}

output "chart_version" {
  description = "Deployed Helm chart version"
  value       = helm_release.pgdog.version
}
