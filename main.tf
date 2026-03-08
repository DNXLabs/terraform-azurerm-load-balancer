resource "azurerm_resource_group" "this" {
  for_each = var.resource_group.create ? { "this" = var.resource_group } : {}
  name     = each.value.name
  location = each.value.location
  tags     = local.tags
}

resource "terraform_data" "validate" {
  input = {
    frontends = keys(local.frontends_by_name)
    pools     = keys(local.backend_pools_by_name)
    probes    = keys(local.probes_by_name)
    rules     = keys(local.rules_by_name)
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for r in var.rules : contains(keys(local.frontends_by_name), r.frontend_ip_configuration_name)
      ])
      error_message = "rules: each rule.frontend_ip_configuration_name must match a defined load_balancer.frontends[].name"
    }

    precondition {
      condition = alltrue([
        for r in var.rules : (
          try(r.backend_pool_name, null) == null || contains(keys(local.backend_pools_by_name), r.backend_pool_name)
        )
      ])
      error_message = "rules: backend_pool_name must match one of backend_pools[].name"
    }

    precondition {
      condition = alltrue([
        for r in var.rules : (
          try(r.probe_name, null) == null || contains(keys(local.probes_by_name), r.probe_name)
        )
      ])
      error_message = "rules: probe_name must match one of probes[].name"
    }

    precondition {
      condition = alltrue([
        for n in var.nat_rules : (
          contains(keys(local.frontends_by_name), n.frontend_ip_configuration_name)
        )
      ])
      error_message = "nat_rules: frontend_ip_configuration_name must match a defined load_balancer.frontends[].name"
    }

    precondition {
      condition = alltrue([
        for n in var.nat_rules : (
          try(n.backend_pool_name, null) == null || contains(keys(local.backend_pools_by_name), n.backend_pool_name)
        )
      ])
      error_message = "nat_rules: backend_pool_name must match one of backend_pools[].name"
    }
  }
}

resource "azurerm_public_ip" "this" {
  for_each            = local.create_public_ip ? { "this" = true } : {}
  name                = local.public_ip_name
  location            = local.rg_loc
  resource_group_name = local.rg_name

  allocation_method = try(var.load_balancer.public_ip.allocation_method, "Static")
  sku               = try(var.load_balancer.public_ip.sku, "Standard")
  sku_tier          = try(var.load_balancer.public_ip.sku_tier, "Regional")
  zones             = try(var.load_balancer.public_ip.zones, null)

  tags = local.tags
}

resource "azurerm_lb" "this" {
  name                = local.lb_name
  location            = local.rg_loc
  resource_group_name = local.rg_name

  sku       = try(var.load_balancer.sku, "Standard")
  sku_tier  = try(var.load_balancer.sku_tier, "Regional")
  edge_zone = try(var.load_balancer.edge_zone, null)

  dynamic "frontend_ip_configuration" {
    for_each = local.frontends_by_name
    content {
      name  = frontend_ip_configuration.value.name
      zones = try(frontend_ip_configuration.value.zones, null)

      subnet_id                     = try(frontend_ip_configuration.value.subnet_id, null)
      private_ip_address_allocation = try(frontend_ip_configuration.value.private_ip_address_allocation, null)
      private_ip_address            = try(frontend_ip_configuration.value.private_ip_address, null)
      private_ip_address_version    = try(frontend_ip_configuration.value.private_ip_address_version, null)

      public_ip_address_id = (try(frontend_ip_configuration.value.public_ip_address_id, null) != null ? frontend_ip_configuration.value.public_ip_address_id : (local.create_public_ip ? azurerm_public_ip.this["this"].id : null))

      public_ip_prefix_id = try(frontend_ip_configuration.value.public_ip_prefix_id, null)

      gateway_load_balancer_frontend_ip_configuration_id = try(frontend_ip_configuration.value.gateway_load_balancer_frontend_ip_configuration_id, null)
    }
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [frontend_ip_configuration]
  }

  depends_on = [terraform_data.validate]
}

resource "azurerm_lb_backend_address_pool" "this" {
  for_each = local.backend_pools_by_name

  loadbalancer_id = azurerm_lb.this.id
  name            = each.value.name

  virtual_network_id = try(each.value.virtual_network_id, null)
  synchronous_mode   = try(each.value.synchronous_mode, null)

  dynamic "tunnel_interface" {
    for_each = try(each.value.tunnel_interfaces, [])
    content {
      identifier = tunnel_interface.value.identifier
      type       = tunnel_interface.value.type
      protocol   = tunnel_interface.value.protocol
      port       = tunnel_interface.value.port
    }
  }
}

resource "azurerm_lb_probe" "this" {
  for_each = local.probes_by_name

  loadbalancer_id = azurerm_lb.this.id
  name            = each.value.name

  protocol            = try(each.value.protocol, "Tcp")
  port                = each.value.port
  request_path        = try(each.value.request_path, null)
  interval_in_seconds = try(each.value.interval_in_seconds, null)
  number_of_probes    = try(each.value.number_of_probes, null)
  probe_threshold     = try(each.value.probe_threshold, null)
}

resource "azurerm_lb_rule" "this" {
  for_each = local.rules_by_name

  loadbalancer_id = azurerm_lb.this.id
  name            = each.value.name

  protocol                       = each.value.protocol
  frontend_port                  = each.value.frontend_port
  backend_port                   = each.value.backend_port
  frontend_ip_configuration_name = each.value.frontend_ip_configuration_name

  backend_address_pool_ids = coalesce(
    try(each.value.backend_pool_ids, null),
    try(each.value.backend_pool_name, null) != null ? [azurerm_lb_backend_address_pool.this[each.value.backend_pool_name].id] : null
  )

  probe_id = coalesce(
    try(each.value.probe_id, null),
    try(each.value.probe_name, null) != null ? azurerm_lb_probe.this[each.value.probe_name].id : null
  )

  idle_timeout_in_minutes = try(each.value.idle_timeout_in_minutes, null)
  load_distribution       = try(each.value.load_distribution, null)
  disable_outbound_snat   = try(each.value.disable_outbound_snat, null)
  floating_ip_enabled     = try(each.value.floating_ip_enabled, null)
  tcp_reset_enabled       = try(each.value.tcp_reset_enabled, null)
}

resource "azurerm_lb_nat_rule" "this" {
  for_each = local.nat_rules_by_name

  resource_group_name = local.rg_name
  loadbalancer_id     = azurerm_lb.this.id
  name                = each.value.name

  protocol                       = each.value.protocol
  frontend_ip_configuration_name = each.value.frontend_ip_configuration_name

  frontend_port       = try(each.value.frontend_port, null)
  frontend_port_start = try(each.value.frontend_port_start, null)
  frontend_port_end   = try(each.value.frontend_port_end, null)

  backend_port = each.value.backend_port

  backend_address_pool_id = coalesce(
    try(each.value.backend_address_pool_id, null),
    try(each.value.backend_pool_name, null) != null ? azurerm_lb_backend_address_pool.this[each.value.backend_pool_name].id : null
  )

  idle_timeout_in_minutes = try(each.value.idle_timeout_in_minutes, null)
  floating_ip_enabled     = try(each.value.floating_ip_enabled, null)
  tcp_reset_enabled       = try(each.value.tcp_reset_enabled, null)
}

resource "azurerm_network_interface_backend_address_pool_association" "this" {
  for_each = {
    for a in var.backend_pool_associations :
    "${a.network_interface_id}.${a.ip_configuration_name}.${a.pool_name}" => a
  }

  network_interface_id    = each.value.network_interface_id
  ip_configuration_name   = each.value.ip_configuration_name
  backend_address_pool_id = azurerm_lb_backend_address_pool.this[each.value.pool_name].id
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = local.diag_enabled ? { "this" = true } : {}

  name                           = "diag-${local.lb_name}"
  target_resource_id             = azurerm_lb.this.id
  log_analytics_workspace_id     = try(var.diagnostics.log_analytics_workspace_id, null)
  storage_account_id             = try(var.diagnostics.storage_account_id, null)
  eventhub_authorization_rule_id = try(var.diagnostics.eventhub_authorization_rule_id, null)

  enabled_log { category = "LoadBalancerAlertEvent" }
  enabled_log { category = "LoadBalancerProbeHealthStatus" }

  enabled_metric {
    category = "AllMetrics"
  }
}
