output "resource_group_name" {
  description = "Resource Group where the Load Balancer is deployed."
  value       = local.rg_name
}

output "load_balancer" {
  description = "Load Balancer outputs."
  value = {
    id   = azurerm_lb.this.id
    name = azurerm_lb.this.name
    sku  = try(var.load_balancer.sku, "Standard")

    private_ip_address   = try(azurerm_lb.this.private_ip_address, null)
    private_ip_addresses = try(azurerm_lb.this.private_ip_addresses, [])

    frontend_ip_configuration_ids = {
      for f in azurerm_lb.this.frontend_ip_configuration :
      f.name => f.id
    }

    backend_pool_ids = {
      for k, v in azurerm_lb_backend_address_pool.this :
      k => v.id
    }

    probe_ids = {
      for k, v in azurerm_lb_probe.this :
      k => v.id
    }

    rule_ids = {
      for k, v in azurerm_lb_rule.this :
      k => v.id
    }

    nat_rule_ids = {
      for k, v in azurerm_lb_nat_rule.this :
      k => v.id
    }

    public_ip = local.create_public_ip ? {
      id         = azurerm_public_ip.this["this"].id
      ip_address = azurerm_public_ip.this["this"].ip_address
      fqdn       = try(azurerm_public_ip.this["this"].fqdn, null)
    } : null
  }
}

output "resource" {
  description = "Generic resource output (standardized across platform modules)."
  value = {
    id   = azurerm_lb.this.id
    name = azurerm_lb.this.name
    type = "Microsoft.Network/loadBalancers"
  }
}