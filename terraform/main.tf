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

module "gke" {
  source = "./modules/gke"

  project_id               = var.project_id
  cluster_name             = "k8-lab"
  zone                     = var.zone
  node_zones               = var.node_zones
  network_id               = module.network.network_id
  subnet_id                = module.network.subnet_id
  pod_secondary_range_name = module.network.pod_secondary_range_name
  node_service_account_id  = "k8-lab-nodes"

  node_pool_name = "general"
  machine_type   = "e2-standard-2"

  # Two so an evicted replica has somewhere to land, which the budgets need.
  min_node_count = 2
  max_node_count = 3
  disk_size_gb   = 50

  # Node replacements land at night in Helsinki rather than at random.
  maintenance_start_time = "01:00"

  deletion_protection = true

  resource_labels = {
    managed_by  = "terraform"
    environment = "dev"
  }

  depends_on = [module.network]
}

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

module "delivery" {
  source = "./modules/delivery"

  project_id        = var.project_id
  region            = var.region
  repository_id     = "k8-lab"
  github_repository = "sindredg/k8-lab"

  depends_on = [google_project_service.required, module.registry]
}

module "gateway" {
  source = "./modules/gateway"

  project_id     = var.project_id
  project_number = var.project_number
  address_name   = "k8-lab-gateway"
  domain         = var.domain

  depends_on = [google_project_service.required]
}

module "observability" {
  source = "./modules/observability"

  project_id   = var.project_id
  domain       = var.domain
  alert_email  = var.alert_email
  cluster_name = module.gke.cluster_name
  namespace    = "demo"

  depends_on = [google_project_service.required, module.gke, module.gateway]
}
