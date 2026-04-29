locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    "Project"     = var.project_name
    "Environment" = var.environment
    "ManagedBy"   = "terraform"
  }
}

# --- OKE Cluster ---
resource "oci_containerengine_cluster" "main" {
  compartment_id     = var.compartment_id
  kubernetes_version = var.k8s_version
  name               = "${local.name_prefix}-oke"
  vcn_id             = var.vcn_id

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = var.public_subnet_id
  }

  options {
    service_lb_subnet_ids = [var.public_subnet_id]

    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
  }

  freeform_tags = local.common_tags
}

# --- Get available OKE node images ---
data "oci_containerengine_node_pool_option" "main" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

locals {
  # Find the latest OKE Oracle Linux image for the k8s version
  node_source_images = [
    for s in data.oci_containerengine_node_pool_option.main.sources :
    s if length(regexall("Oracle-Linux-[0-9]", s.source_name)) > 0 && length(regexall(var.k8s_version, s.source_name)) > 0
  ]
}

# --- Node Pool ---
resource "oci_containerengine_node_pool" "main" {
  compartment_id     = var.compartment_id
  cluster_id         = oci_containerengine_cluster.main.id
  kubernetes_version = var.k8s_version
  name               = "${local.name_prefix}-nodepool"
  node_shape         = var.node_shape

  node_shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gb
  }

  node_source_details {
    source_type = "IMAGE"
    image_id    = local.node_source_images[0].image_id
  }

  node_config_details {
    size = var.node_count

    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = var.worker_subnet_id
    }

    freeform_tags = merge(local.common_tags, {
      "oke-nodepool" = "${local.name_prefix}-nodepool"
    })
  }

  initial_node_labels {
    key   = "environment"
    value = var.environment
  }

  initial_node_labels {
    key   = "project"
    value = var.project_name
  }

  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : null

  freeform_tags = local.common_tags
}

# --- Data Sources ---
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

data "oci_containerengine_cluster_kube_config" "main" {
  cluster_id = oci_containerengine_cluster.main.id
}
