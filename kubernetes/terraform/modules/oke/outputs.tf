output "cluster_id" {
  description = "OCID of the OKE cluster"
  value       = oci_containerengine_cluster.main.id
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = oci_containerengine_cluster.main.endpoints[0].kubernetes
}

output "node_pool_id" {
  description = "OCID of the node pool"
  value       = oci_containerengine_node_pool.main.id
}

output "kubeconfig" {
  description = "Kubeconfig content for the cluster"
  value       = data.oci_containerengine_cluster_kube_config.main.content
  sensitive   = true
}
