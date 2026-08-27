locals {
  pod_secondary_range_name = "${var.subnet_name}-pods"
}

resource "google_compute_network" "main" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "main" {
  name                     = var.subnet_name
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.main.id
  ip_cidr_range            = var.node_ipv4_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = local.pod_secondary_range_name
    ip_cidr_range = var.pod_ipv4_cidr
  }
}