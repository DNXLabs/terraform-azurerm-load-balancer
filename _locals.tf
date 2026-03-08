locals {
  prefix = var.name

  default_tags = {
    name      = var.name
    managedBy = "terraform"
  }

  tags = merge(local.default_tags, var.tags)

  rg_name = var.resource_group.create ? azurerm_resource_group.this["this"].name : data.azurerm_resource_group.existing[0].name
  rg_loc  = var.resource_group.create ? azurerm_resource_group.this["this"].location : (try(var.resource_group.location, null) != null ? var.resource_group.location : data.azurerm_resource_group.existing[0].location)

  lb_name_raw = "lb-${local.prefix}-${try(var.load_balancer.name_suffix, "001")}"
  lb_name     = coalesce(try(var.load_balancer.name, null), substr(replace(lower(local.lb_name_raw), "/[^0-9a-z-]/", ""), 0, 80))

  backend_pools_by_name = { for p in var.backend_pools : p.name => p }
  probes_by_name        = { for p in var.probes : p.name => p }

  create_public_ip = try(var.load_balancer.public_ip.enabled, false)
  public_ip_name   = coalesce(try(var.load_balancer.public_ip.name, null), "pip-lb-${local.prefix}-${try(var.load_balancer.name_suffix, "001")}")

  frontends_by_name = { for f in var.load_balancer.frontends : f.name => f }

  rules_by_name     = { for r in var.rules : r.name => r }
  nat_rules_by_name = { for r in var.nat_rules : r.name => r }

  diag_enabled = try(var.diagnostics.enabled, false) && (try(var.diagnostics.log_analytics_workspace_id, null) != null || try(var.diagnostics.storage_account_id, null) != null || try(var.diagnostics.eventhub_authorization_rule_id, null) != null)
}