terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.59.0, <= 4.00"
    }
  }
  required_version = ">= 0.13"
}
