terraform {
    required_providers {
    digitalocean = {
        source = "digitalocean/digitalocean"
        version = "~> 2.0"
    }
  }
    backend "s3" {
        skip_credentials_validation = true
        skip_metadata_api_check = true
        skip_region_validation = true
    }
}

provider "digitalocean" {}
variable "region" {}
variable "environment" {}
variable "talosos-image" {}
variable "talosos-version" {}

resource "random_id" "deploy_id" {
    byte_length = 8
}

locals {
    id = random_id.deploy_id.hex
}

resource "digitalocean_spaces_bucket" "artifacts" {
  name   = "artifacts-${local.id}"
  region = var.region
}

resource "digitalocean_spaces_bucket_object" "talosos-image" {
  region = digitalocean_spaces_bucket.artifacts.region
  bucket = digitalocean_spaces_bucket.artifacts.name
  key = "talosos/${var.talosos-version}/digital-ocean-amd64.raw.gz"
  source = var.talosos-image
  etag = filemd5(var.talosos-image)
  acl = "public-read"
}

resource "digitalocean_custom_image" "talosos-image" {
    name = "talosos-${var.talosos-version}-${local.id}"
    url = "https://${digitalocean_spaces_bucket.artifacts.bucket_domain_name}/${digitalocean_spaces_bucket_object.talosos-image.key}"
    regions = [var.region]
}

resource "digitalocean_loadbalancer" "control-plane" {
    name = "control-plane"
    region = var.region
    healthcheck {
        port = 6443
        protocol = "tcp"
        check_interval_seconds = 10
        response_timeout_seconds = 5
        healthy_threshold = 5
        unhealthy_threshold = 3
    }
    forwarding_rule {
        entry_protocol = "tcp"
        entry_port = 443
        target_protocol = "tcp"
        target_port = 6443
    }
}

data external "cluster-config" {
    program = ["bash","../scripts/cluster-config"]
    query = {
        name = local.id
        environment = var.environment
        ip = digitalocean_loadbalancer.control-plane.ip
    }
}

output "control-plane-ip" {
    value = digitalocean_loadbalancer.control-plane.ip
}
