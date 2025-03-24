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
  tags = {
    pmtest = "policytest"
  }
}

resource "azurerm_container_registry" "mikeo" {
  name                = "mikeoregistry"
  resource_group_name = azurerm_resource_group.mikeo.name
  location            = azurerm_resource_group.mikeo.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_key_vault" "mikeo" {
  name                = "mikeokeyvault2"
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
      image  = "${azurerm_container_registry.mikeo.login_server}/myapp:latest"
      cpu    = 0.25
      memory = "0.5Gi"
      # registry {
      #   server               = azurerm_container_registry.acr.login_server
      #   username             = azurerm_container_registry.acr.admin_username
      #   password_secret_name = "registry"
      # }
    }
  }
  registry {
    server               = azurerm_container_registry.mikeo.login_server
    username             = azurerm_container_registry.mikeo.admin_username
    password_secret_name = "registry"    
  }

  secret {
    name  = "registry"
    value = azurerm_container_registry.mikeo.admin_password
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.mikeo.id]
  }

  depends_on = [azurerm_user_assigned_identity.mikeo, azurerm_role_assignment.acr_pull, azurerm_key_vault_secret.reg_pw]
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
  for_each             = { AcrPull = "", Reader = "" }
  principal_id         = azurerm_user_assigned_identity.mikeo.principal_id
  role_definition_name = each.key
  scope                = azurerm_container_registry.mikeo.id
}

resource "azurerm_key_vault_secret" "reg_pw" {
  key_vault_id = azurerm_key_vault.mikeo.id
  name         = "mikeoregistry-pw"
  value        = azurerm_container_registry.mikeo.admin_password
}

# notes
# running TF as myself
# added secrets privs to myself (legacy policy model)
# added secrets privs to idnetity (legacy policy model)

# Create the Event Hub Namespace
resource "azurerm_eventhub_namespace" "mikeo_ns" {
  name                = "mikeo-namespace"
  location            = azurerm_resource_group.mikeo.location
  resource_group_name = azurerm_resource_group.mikeo.name
  sku                 = "Standard"
  local_authentication_enabled = false  # disables access keys
  capacity            = 1
  tags = {
    environment = "dev"
  }
}

# Create the Event Hub within the namespace
resource "azurerm_eventhub" "mikeo_hub" {
  name                = "mikeo-eventhub"
  namespace_name      = azurerm_eventhub_namespace.mikeo_ns.name
  resource_group_name = azurerm_resource_group.mikeo.name
  partition_count     = 2
  message_retention   = 1
}

# Grant the User Assigned Identity Data Owner permissions to the Event Hub Namespace
resource "azurerm_role_assignment" "mikeo_eventhub_data_owner" {
  scope                = azurerm_eventhub_namespace.mikeo_ns.id
  role_definition_name = "Azure Event Hubs Data Owner"
  principal_id         = azurerm_user_assigned_identity.mikeo.principal_id
}
