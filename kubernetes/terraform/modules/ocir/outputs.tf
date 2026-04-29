output "repository_id" {
  description = "OCID of the container repository"
  value       = oci_artifacts_container_repository.this.id
}

output "repository_path" {
  description = "Full path of the container repository"
  value       = oci_artifacts_container_repository.this.display_name
}
