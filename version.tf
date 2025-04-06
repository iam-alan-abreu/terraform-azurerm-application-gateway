terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 04.00, <= 5.00"
    }
  }
  required_version = ">= 0.13"
}
