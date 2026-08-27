# Creates the dedicated VPC, subnet, and Pod address range used by GKE.
module "network" {
  source = "./modules/network"

  project_id     = var.project_id
  region         = var.region
  network_name   = "gke-vpc"
  subnet_name    = "gke-subnet"
  node_ipv4_cidr = "10.10.0.0/20"
  pod_ipv4_cidr  = "10.20.0.0/16"

  depends_on = [google_project_service.required]
}