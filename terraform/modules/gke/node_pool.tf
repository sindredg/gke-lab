# A separately managed autoscaling node pool on private Shielded VMs.
resource "google_container_node_pool" "general" {
  project  = var.project_id
  name     = var.node_pool_name
  location = var.zone
  cluster  = google_container_cluster.main.name

  # Every zone listed, so a ZONE_RESOURCE_POOL_EXHAUSTED falls to another.
  node_locations = var.node_zones

  # Creation size only, and ForceNew, so it stays at 1 while the floor moves.
  initial_node_count = 1

  autoscaling {
    total_min_node_count = var.min_node_count
    total_max_node_count = var.max_node_count
    location_policy      = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  network_config {
    enable_private_nodes = true
  }

  node_config {
    machine_type = var.machine_type
    image_type   = "COS_CONTAINERD"
    disk_type    = "pd-balanced"
    disk_size_gb = var.disk_size_gb

    service_account = google_service_account.nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    metadata = {
      "disable-legacy-endpoints" = "true"
    }

    labels = merge(var.resource_labels, {
      node_pool = var.node_pool_name
    })
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  # ForceNew and drifts on a manual resize, which would plan a pool delete.
  lifecycle {
    ignore_changes = [initial_node_count]
  }

  depends_on = [google_project_iam_member.nodes]
}
