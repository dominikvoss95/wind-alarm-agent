# Terraform Infrastructure for Wind Alarm Agent on Microsoft Azure

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "rg-wind-alarm-agent"
  location = "westeurope"
}

# Azure AI Foundry / Cognitive Services Account
resource "azurerm_cognitive_account" "ai_services" {
  name                = "cog-wind-alarm-agent"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "AIServices"
  sku_name            = "S0"
}

# GPT-4o-mini Deployment for Vision OCR & Forecast Analysis
resource "azurerm_cognitive_deployment" "gpt_4o_mini" {
  name                 = "gpt-4o-mini"
  cognitive_account_id = azurerm_cognitive_account.ai_services.id
  model {
    format  = "OpenAI"
    name    = "gpt-4o-mini"
    version = "2024-07-18"
  }
  sku {
    name = "Standard"
  }
}

# Storage Account for static assets & Function app runtime
resource "azurerm_storage_account" "storage" {
  name                     = "stwindalarmagent"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Container for public JSON assets (measurements.json, forecast.json, history)
resource "azurerm_storage_container" "assets" {
  name                  = "wind-alarm-assets"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "blob" # Public read access for blob files
}

# Cosmos DB Account (NoSQL)
resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "cosmos-wind-alarm-agent"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }
  
  # Enable free tier if applicable (limited to 1 per subscription)
  # enable_free_tier = true
}

# Cosmos DB Database
resource "azurerm_cosmosdb_sql_database" "db" {
  name                = "wind-alarm-db"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
}

# Cosmos DB Container for measurements with TTL support
resource "azurerm_cosmosdb_sql_container" "measurements" {
  name                = "measurements"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  database_name       = azurerm_cosmosdb_sql_database.db.name
  partition_key_path  = "/location_id"
  default_ttl         = 7776000 # 90 days in seconds
}

# App Service Plan for serverless Functions
resource "azurerm_service_plan" "asp" {
  name                = "plan-wind-alarm-agent"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption tier (serverless)
}

# Linux Function App running custom Docker Container (Playwright setup)
resource "azurerm_linux_function_app" "function" {
  name                = "func-wind-alarm-agent"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.storage.name
  storage_account_access_key = azurerm_storage_account.storage.primary_access_key
  service_plan_id            = azurerm_service_plan.asp.id

  site_config {
    application_stack {
      docker {
        registry_url = "mcr.microsoft.com" # Placeholder, replace with your Azure Container Registry (ACR) URL
        image_name   = "wind-alarm-agent"
        image_tag    = "latest"
      }
    }
  }

  app_settings = {
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "USE_AZURE"                           = "true"
    "AZURE_OPENAI_ENDPOINT"               = azurerm_cognitive_account.ai_services.endpoint
    "AZURE_OPENAI_DEPLOYMENT_NAME"        = azurerm_cognitive_deployment.gpt_4o_mini.name
    "AZURE_COSMOS_ENDPOINT"               = azurerm_cosmosdb_account.cosmos.endpoint
    "AZURE_COSMOS_DB"                     = azurerm_cosmosdb_sql_database.db.name
    "AZURE_COSMOS_CONTAINER"              = azurerm_cosmosdb_sql_container.measurements.name
    "AZURE_STORAGE_CONNECTION_STRING"     = azurerm_storage_account.storage.primary_connection_string
    "AZURE_STORAGE_CONTAINER_NAME"        = azurerm_storage_container.assets.name
  }
}
