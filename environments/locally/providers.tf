terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  features {}

  # The Storage Account has shared key access disabled, so the provider can't
  # fetch an account key to read its data-plane properties - it uses Entra ID
  # instead.
  storage_use_azuread = true
}

module "api-management-function-apps" {
  source = "../../modules/api-management-function-apps"

  name_prefix = "locally-example-apimfunc"
  location    = "berlin"
  tags = {
    ProvisionedVia = "Terraform"
  }
}
