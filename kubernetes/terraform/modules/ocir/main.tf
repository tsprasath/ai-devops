resource "oci_artifacts_container_repository" "this" {
  compartment_id = var.compartment_id
  display_name   = "${var.project_name}/${var.service_name}"
  is_public      = var.is_public
  is_immutable   = var.is_immutable
}
