# A Standard VPC-native cluster, private nodes, DNS-only control plane.
resource "google_container_cluster" "main" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.zone

  # A zonal cluster lists only the additional zones, not its own.
  node_locations = [for z in var.node_zones : z if z != var.zone]

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

  # The window decides when a drain happens, not how often. Four hours, UTC.
  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  # WORKLOADS is the billed line here. Control-plane components stay off.
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  # Listed in the API's order, because the provider compares the list in order.
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "HPA", "POD", "DEPLOYMENT", "CADVISOR"]

    managed_prometheus {
      enabled = true
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name = var.pod_secondary_range_name
  }

  private_cluster_config {
    enable_private_nodes = true

    # Derived by GKE, declared so a plan does not propose unsetting it.
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

  # Installs the Gateway API CRDs and the controller that reconciles them.
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # BASIC scans nothing. VULNERABILITY_BASIC reports CVEs in running workloads.
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  resource_labels = var.resource_labels
}
