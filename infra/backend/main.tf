terraform {
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {}
variable "environment" {}
variable "namespace" {}
variable "region" {}

resource "random_id" "deploy_id" {
    byte_length = 8
}

resource "digitalocean_spaces_bucket" "state" {
  name = "${var.namespace}-${var.environment}-${random_id.deploy_id.hex}"
  region = var.region
}

output "endpoint" {
    value = "https://${var.region}.digitaloceanspaces.com"
}

output "region" {
    value = digitalocean_spaces_bucket.state.region
}

output "bucket" {
    value = digitalocean_spaces_bucket.state.name
}

output "key" {
    value = "terraform.tfstate"
}
