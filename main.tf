provider "azurerm" {
  subscription_id = "f939fbbd-cf94-451b-a45c-1be6bc755761"
  features {}
}

resource "azurerm_resource_group" "mikeo" {
  name     = "mikeo-resources"
  location = "East US"
}

resource "azurerm_storage_account" "mikeo" {
  name                     = "mikeostorageacct"
  resource_group_name      = azurerm_resource_group.mikeo.name
  location                 = azurerm_resource_group.mikeo.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_container_registry" "mikeo" {
  name                = "mikeoregistry"
  resource_group_name = azurerm_resource_group.mikeo.name
  location            = azurerm_resource_group.mikeo.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_key_vault" "mikeo" {
  name                = "mikeokeyvault"
  resource_group_name = azurerm_resource_group.mikeo.name
  location            = azurerm_resource_group.mikeo.location
  sku_name            = "standard"
  tenant_id           = data.azurerm_client_config.mikeo.tenant_id
}

resource "azurerm_application_insights" "mikeo" {
  name                = "mikeoappinsights"
  resource_group_name = azurerm_resource_group.mikeo.name
  location            = azurerm_resource_group.mikeo.location
  application_type    = "web"
}

resource "azurerm_monitor_diagnostic_setting" "mikeo" {
  name                       = "mikeo-diagnostic-setting"
  target_resource_id         = azurerm_application_insights.mikeo.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.mikeo.id

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_container_app_environment" "mikeo" {
  name                = "mikeo-environment"
  resource_group_name = azurerm_resource_group.mikeo.name
  location            = azurerm_resource_group.mikeo.location
}

resource "azurerm_container_app" "mikeo" {
  name                         = "mikeo-app"
  container_app_environment_id = azurerm_container_app_environment.mikeo.id
  resource_group_name          = azurerm_resource_group.mikeo.name
  revision_mode                = "Single"

  template {
    container {
      name   = "mikeo-container"
      image  = "${azurerm_container_registry.mikeo.login_server}/mikeo-image:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.mikeo.id]
  }

  depends_on = [ azurerm_role_assignment.acr_pull ]
}

data "azurerm_client_config" "mikeo" {}

resource "azurerm_log_analytics_workspace" "mikeo" {
  name                = "mikeo-law"
  resource_group_name = azurerm_resource_group.mikeo.name
  location            = azurerm_resource_group.mikeo.location
  retention_in_days   = 30
}

resource "azurerm_user_assigned_identity" "mikeo" {
  name                = "mikeo-identity"
  resource_group_name = azurerm_resource_group.mikeo.name
  location            = azurerm_resource_group.mikeo.location
}

resource "azurerm_role_assignment" "acr_pull" {
  principal_id          = azurerm_user_assigned_identity.mikeo.principal_id
  role_definition_name  = "AcrPull"
  scope                 = azurerm_container_registry.mikeo.id
}
