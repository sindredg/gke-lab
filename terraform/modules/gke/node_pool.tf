# Creates a separately managed, autoscaling node pool using private Shielded VMs.
resource "google_container_node_pool" "general" {
  project  = var.project_id
  name     = var.node_pool_name
  location = var.zone
  cluster  = google_container_cluster.main.name

  # Only the size the pool is created at; autoscaling owns the count from then on.
  # The field forces a new node pool when it changes, so it stays at one rather than
  # tracking the floor, where raising the floor would replace the pool instead of
  # resizing it.
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

  # initial_node_count is ForceNew. It is pinned to 1 above so the floor can move
  # without replacing the pool, but a manual resize writes the live count back into
  # state, and the difference then proposes destroying the pool. Phase 9 raised the
  # floor by resizing by hand, which armed exactly that. The field only matters when
  # the pool is created, so drift on it is not worth a plan that offers to delete
  # both nodes.
  lifecycle {
    ignore_changes = [initial_node_count]
  }

  depends_on = [google_project_iam_member.nodes]
}