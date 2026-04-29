output "vault_id" {
  description = "OCID of the vault"
  value       = oci_kms_vault.this.id
}

output "key_id" {
  description = "OCID of the master encryption key"
  value       = oci_kms_key.master.id
}

output "jwt_secret_id" {
  description = "OCID of the JWT secret"
  value       = oci_vault_secret.jwt_secret.id
}
