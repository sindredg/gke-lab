# Creates a Standard VPC-native GKE cluster with private nodes and DNS-only control-plane access.
resource "google_container_cluster" "main" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.zone

  network    = var.network_id
  subnetwork = var.subnet_id

  networking_mode   = "VPC_NATIVE"
  datapath_provider = "ADVANCED_DATAPATH"

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = var.deletion_protection
  enable_shielded_nodes    = true

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    cluster_secondary_range_name = var.pod_secondary_range_name
  }

  private_cluster_config {
    enable_private_nodes = true

    # Derived by GKE from the disabled IP endpoints below. Declared here so a
    # plan does not propose unsetting it on every run.
    enable_private_endpoint = true
  }

  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
    }

    ip_endpoints_config {
      enabled = false
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  resource_labels = var.resource_labels
}
