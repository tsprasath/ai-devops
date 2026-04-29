output "vcn_id" {
  description = "OCID of the VCN"
  value       = oci_core_vcn.main.id
}

output "public_subnet_id" {
  description = "OCID of the public subnet"
  value       = oci_core_subnet.public.id
}

output "worker_subnet_id" {
  description = "OCID of the private worker subnet"
  value       = oci_core_subnet.private_workers.id
}

output "pod_subnet_id" {
  description = "OCID of the private pod subnet"
  value       = oci_core_subnet.private_pods.id
}

output "nat_gateway_id" {
  description = "OCID of the NAT gateway"
  value       = oci_core_nat_gateway.main.id
}
