resource "oci_kms_vault" "this" {
  compartment_id = var.compartment_id
  display_name   = "${var.project_name}-${var.environment}-vault"
  vault_type     = var.vault_type
}

resource "oci_kms_key" "master" {
  compartment_id = var.compartment_id
  display_name   = "${var.project_name}-${var.environment}-master-key"
  management_endpoint = oci_kms_vault.this.management_endpoint

  key_shape {
    algorithm = "AES"
    length    = 32
  }

  protection_mode = "HSM"
}

resource "oci_vault_secret" "jwt_secret" {
  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.this.id
  key_id         = oci_kms_key.master.id
  secret_name    = "${var.project_name}-${var.environment}-jwt-secret"

  secret_content {
    content_type = "BASE64"
    content      = base64encode("PLACEHOLDER_CHANGE_ME")
  }

  lifecycle {
    ignore_changes = [secret_content]
  }
}
