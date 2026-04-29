terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
}

provider "oci" {
  region           = var.region
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
}

module "vcn" {
  source         = "../../modules/vcn"
  project_name   = var.project_name
  environment    = "prod"
  compartment_id = var.compartment_id
  region         = var.region
}

module "oke" {
  source         = "../../modules/oke"
  compartment_id = var.compartment_id
  project_name   = var.project_name
  environment    = "prod"
  vcn_id         = module.vcn.vcn_id
  subnet_ids     = module.vcn.subnet_ids
  ssh_public_key = var.ssh_public_key
  node_count     = 5
  node_ocpus     = 4
  node_memory_gb = 64
}

module "ocir" {
  source         = "../../modules/ocir"
  compartment_id = var.compartment_id
  project_name   = var.project_name
  environment    = "prod"
}

module "vault" {
  source         = "../../modules/vault"
  compartment_id = var.compartment_id
  project_name   = var.project_name
  environment    = "prod"
}

module "api_gateway" {
  source         = "../../modules/api-gateway"
  compartment_id = var.compartment_id
  project_name   = var.project_name
  environment    = "prod"
  subnet_id      = module.vcn.public_subnet_id
}

# module "waf" {
#   source           = "../../modules/waf"
#   compartment_id   = var.compartment_id
#   project_name     = var.project_name
#   environment      = "prod"
#   load_balancer_id = "<LB_OCID_AFTER_K8S_DEPLOY>"
# }
