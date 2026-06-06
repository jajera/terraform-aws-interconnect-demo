# =============================================================================
# GCP Network Resources
# =============================================================================

resource "google_compute_network" "this" {
  name                    = "demo-vpc-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "private" {
  name          = "demo-private-subnet"
  ip_cidr_range = var.gcp_vpc_cidr
  region        = var.gcp_region
  network       = google_compute_network.this.id
}

resource "google_compute_firewall" "allow_aws" {
  name    = "demo-allow-aws"
  network = google_compute_network.this.name

  direction     = "INGRESS"
  source_ranges = [var.aws_vpc_cidr]

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = ["demo-instance"]
}

# IAP tunnel SSH to the private GCE instance (no external IP)
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "demo-allow-iap-ssh"
  network = google_compute_network.this.name

  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = ["demo-instance"]
}

# =============================================================================
# GCP Compute
# =============================================================================

resource "tls_private_key" "gce" {
  algorithm = "ED25519"
}

data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

resource "google_compute_instance" "this" {
  name         = "demo-gce-instance"
  machine_type = "e2-micro"
  zone         = "${var.gcp_region}-b"

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
  }

  metadata = {
    "ssh-keys"       = "debian:${tls_private_key.gce.public_key_openssh}"
    "enable-oslogin" = "FALSE"
  }

  tags = ["demo-instance"]

  labels = {
    project     = "terraform-aws-interconnect-demo"
    environment = "demo"
    managed_by  = "terraform"
  }
}
