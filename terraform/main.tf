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

# Creates the private GKE cluster and its separately managed general-purpose node pool.
module "gke" {
  source = "./modules/gke"

  project_id               = var.project_id
  cluster_name             = "k8-lab"
  zone                     = var.zone
  network_id               = module.network.network_id
  subnet_id                = module.network.subnet_id
  pod_secondary_range_name = module.network.pod_secondary_range_name
  node_service_account_id  = "k8-lab-nodes"

  node_pool_name = "general"
  machine_type   = "e2-standard-2"
  min_node_count = 1
  max_node_count = 3
  disk_size_gb   = 50

  deletion_protection = true

  resource_labels = {
    managed_by  = "terraform"
    environment = "dev"
  }

  depends_on = [module.network]
}

# Creates the private image repository and grants the nodes read access to it.
module "registry" {
  source = "./modules/registry"

  project_id                 = var.project_id
  region                     = var.region
  repository_id              = "k8-lab"
  node_service_account_email = module.gke.node_service_account_email

  resource_labels = {
    managed_by  = "terraform"
    environment = "dev"
  }

  depends_on = [google_project_service.required]
}

# Federates GitHub Actions into the project and creates the delivery identity.
module "delivery" {
  source = "./modules/delivery"

  project_id        = var.project_id
  region            = var.region
  repository_id     = "k8-lab"
  github_repository = "sindredg/k8-lab"

  depends_on = [google_project_service.required, module.registry]
}