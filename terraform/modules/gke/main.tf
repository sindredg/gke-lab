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

  # REGULAR with auto_upgrade means GKE replaces nodes under the workload on its own
  # schedule. The window does not reduce how often that happens; it decides when, so
  # a drain is predictable and lands while nobody is reading the page. GKE opens four
  # hours from this start time, given in UTC.
  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  # Both blocks below state what GKE is already doing by default. They are here so the telemetry scope is a recorded choice rather than an inherited one, which means a plan that proposes a change is reporting that the default was not what was assumed.

  # Container stdout is the largest ingest line on a cluster this size and Cloud Logging bills it, so WORKLOADS is a cost decision, not a free one. The control-plane components (API_SERVER, SCHEDULER, CONTROLLER_MANAGER) stay off: useful for "who changed this object", noisy and billable for everything else.
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  # Workload metrics come from Managed Service for Prometheus rather than the legacy per-workload components. Advanced datapath observability is a separate toggle with its own cost and answers no question this platform is asking yet.
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]

    managed_prometheus {
      enabled = true
    }
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

  # Installs the Gateway API CRDs and starts the controller that reconciles them into Google Cloud load balancers.
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  resource_labels = var.resource_labels
}
