output "cluster_endpoint" {
  description = "OKE cluster API endpoint"
  value       = module.oke.cluster_endpoint
}

output "gateway_hostname" {
  description = "API Gateway hostname"
  value       = module.api_gateway.gateway_hostname
}

output "ocir_repo" {
  description = "OCIR repository URL"
  value       = module.ocir.repository_url
}

output "vault_id" {
  description = "OCI Vault OCID"
  value       = module.vault.vault_id
}
