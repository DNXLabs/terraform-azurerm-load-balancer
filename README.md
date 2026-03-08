# terraform-azurerm-load-balancer

Terraform module for creating and managing Azure Load Balancers with support for internal (private) and public frontends, multiple backend pools, health probes, load balancing rules, NAT rules, and optional NIC associations.

This module supports all SKU types (Basic, Standard, Gateway) and provides built-in validation to prevent misconfigured rules and references.

## Features

- **Internal & Public Load Balancers**: Support for private (subnet) and public (PIP) frontends
- **Multiple Frontends**: Configure multiple frontend IP configurations
- **Backend Address Pools**: Multiple pools with optional VNet associations and tunnel interfaces
- **Health Probes**: TCP, HTTP, and HTTPS health probes with configurable thresholds
- **Load Balancing Rules**: Flexible rules with frontend/backend/probe references
- **Inbound NAT Rules**: Single port and port range mappings for individual VM access
- **NIC Associations**: Direct NIC-to-backend pool associations for standalone VMs
- **Public IP Management**: Optional automatic public IP creation
- **Diagnostic Settings**: Optional Azure Monitor integration (Log Analytics, Storage, Event Hub)
- **Built-in Validations**: Preconditions ensure frontend, backend pool, and probe references are valid
- **Resource Group Flexibility**: Create new or use existing resource groups
- **Tagging Strategy**: Built-in default tagging with custom tag support

## Usage

### Example 1 — Non-Prod (Internal Load Balancer)

A simple internal load balancer for distributing traffic within a VNet.

```hcl
module "loadbalancer" {
  source = "./modules/loadbalancer"

  name = "mycompany-dev-aue-app"

  resource_group = {
    create   = false
    name     = "rg-mycompany-dev-aue-app-001"
    location = "australiaeast"
  }

  tags = {
    project     = "my-app"
    environment = "development"
  }

  load_balancer = {
    sku = "Standard"

    frontends = [
      {
        name                          = "fe-internal"
        subnet_id                     = "/subscriptions/xxxx/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-dev/subnets/snet-app"
        private_ip_address_allocation = "Dynamic"
      }
    ]
  }

  backend_pools = [
    {
      name = "be-app"
    }
  ]

  probes = [
    {
      name     = "probe-http"
      protocol = "Http"
      port     = 80
      request_path = "/health"
    }
  ]

  rules = [
    {
      name                           = "rule-http"
      protocol                       = "Tcp"
      frontend_port                  = 80
      backend_port                   = 80
      frontend_ip_configuration_name = "fe-internal"
      backend_pool_name              = "be-app"
      probe_name                     = "probe-http"
    }
  ]
}
```

### Example 2 — Production (Public Load Balancer with NAT Rules)

A production load balancer with public frontend, multiple rules, and NAT rules for SSH access.

```hcl
module "loadbalancer" {
  source = "./modules/loadbalancer"

  name = "contoso-prod-aue-web"

  resource_group = {
    create   = true
    name     = "rg-contoso-prod-aue-web-001"
    location = "australiaeast"
  }

  tags = {
    project     = "web-platform"
    environment = "production"
    compliance  = "soc2"
  }

  load_balancer = {
    sku      = "Standard"
    sku_tier = "Regional"

    frontends = [
      {
        name  = "fe-public"
        zones = ["1", "2", "3"]
      }
    ]

    public_ip = {
      enabled           = true
      allocation_method = "Static"
      sku               = "Standard"
      sku_tier          = "Regional"
      zones             = ["1", "2", "3"]
    }
  }

  backend_pools = [
    {
      name = "be-web"
    },
    {
      name = "be-api"
    }
  ]

  probes = [
    {
      name                = "probe-web"
      protocol            = "Https"
      port                = 443
      request_path        = "/health"
      interval_in_seconds = 15
      number_of_probes    = 2
    },
    {
      name     = "probe-api"
      protocol = "Tcp"
      port     = 8080
    }
  ]

  rules = [
    {
      name                           = "rule-https"
      protocol                       = "Tcp"
      frontend_port                  = 443
      backend_port                   = 443
      frontend_ip_configuration_name = "fe-public"
      backend_pool_name              = "be-web"
      probe_name                     = "probe-web"
      idle_timeout_in_minutes        = 15
      disable_outbound_snat          = true
      tcp_reset_enabled              = true
    },
    {
      name                           = "rule-api"
      protocol                       = "Tcp"
      frontend_port                  = 8080
      backend_port                   = 8080
      frontend_ip_configuration_name = "fe-public"
      backend_pool_name              = "be-api"
      probe_name                     = "probe-api"
    }
  ]

  nat_rules = [
    {
      name                           = "nat-ssh-vm1"
      protocol                       = "Tcp"
      frontend_ip_configuration_name = "fe-public"
      frontend_port                  = 50001
      backend_port                   = 22
    },
    {
      name                           = "nat-ssh-vm2"
      protocol                       = "Tcp"
      frontend_ip_configuration_name = "fe-public"
      frontend_port                  = 50002
      backend_port                   = 22
    }
  ]

  diagnostics = {
    enabled                    = true
    log_analytics_workspace_id = "/subscriptions/xxxx/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/law-prod"
  }
}
```

### Using YAML Variables

Create a `vars/platform.yaml` file:

```yaml
azure:
  subscription_id: "afb35bd4-145f-4a15-889e-5da052d030ce"
  location: australiaeast

network_lookup:
  resource_group_name: "rg-managed-services-lab-aue-stg-001"
  vnet_name: "vnet-managed-services-lab-aue-stg-001"

platform:
  load_balancers:
    web-lb:
      naming:
        org: managed-services
        env: lab
        region: aue
        workload: stg

      resource_group:
        create: false
        name: rg-managed-services-lab-aue-stg-001
        location: australiaeast

      load_balancer:
        sku: Standard
        frontends:
          - name: fe-internal
            subnet_name: snet-stg-app
            private_ip_address_allocation: Dynamic

      backend_pools:
        - name: be-app

      probes:
        - name: probe-http
          protocol: Http
          port: 80
          request_path: /health

      rules:
        - name: rule-http
          protocol: Tcp
          frontend_port: 80
          backend_port: 80
          frontend_ip_configuration_name: fe-internal
          backend_pool_name: be-app
          probe_name: probe-http
```

Then use in your Terraform:

```hcl
locals {
  workspace = yamldecode(file("vars/${terraform.workspace}.yaml"))
}

data "azurerm_subnet" "app" {
  name                 = "snet-stg-app"
  virtual_network_name = local.workspace.network_lookup.vnet_name
  resource_group_name  = local.workspace.network_lookup.resource_group_name
}

module "loadbalancer" {
  for_each = try(local.workspace.platform.load_balancers, {})

  source = "./modules/loadbalancer"

  name           = "${each.value.naming.org}-${each.value.naming.env}-${each.value.naming.region}-${each.value.naming.workload}"
  resource_group = each.value.resource_group
  tags           = try(each.value.tags, {})

  load_balancer = each.value.load_balancer

  backend_pools = try(each.value.backend_pools, [])
  probes        = try(each.value.probes, [])
  rules         = try(each.value.rules, [])
  nat_rules     = try(each.value.nat_rules, [])
  diagnostics   = try(each.value.diagnostics, {})
}
```

## Load Balancer SKUs

| SKU | Description | Use Case |
|-----|-------------|----------|
| `Basic` | Basic features, no SLA | Development/testing |
| `Standard` | Zone-redundant, SLA-backed | Production workloads |
| `Gateway` | Gateway Load Balancer | NVA chaining scenarios |

## Frontend Types

### Internal (Private)

```hcl
frontends = [
  {
    name                          = "fe-internal"
    subnet_id                     = data.azurerm_subnet.app.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.100"
  }
]
```

### Public

```hcl
frontends = [
  {
    name = "fe-public"
  }
]

public_ip = {
  enabled           = true
  allocation_method = "Static"
  sku               = "Standard"
}
```

## Naming Convention

Resources are named using the prefix pattern: `{name}`

Example:
- Load Balancer: `lb-{name}-001`
- Public IP: `pip-lb-{name}-001`

## Outputs

| Name | Description |
|------|-------------|
| `resource_group_name` | Resource Group where the Load Balancer is deployed |
| `load_balancer` | LB object with id, name, sku, IPs, frontend/backend/probe/rule/NAT IDs |
| `resource` | Generic resource output (id, name, type) |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | >= 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | >= 4.0.0 |

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `name` | Resource name prefix for all resources | string | yes |
| `resource_group` | Resource group configuration | object | yes |
| `load_balancer` | Load Balancer configuration (SKU, frontends, public IP) | object | yes |
| `tags` | Extra tags merged with default tags | map(string) | no |
| `diagnostics` | Azure Monitor diagnostic settings | object | no |
| `backend_pools` | Backend address pools | list(object) | no |
| `probes` | Health probes | list(object) | no |
| `rules` | Load balancing rules | list(object) | no |
| `nat_rules` | Inbound NAT rules | list(object) | no |
| `backend_pool_associations` | NIC-to-backend pool associations | list(object) | no |

### Detailed Input Specifications

#### load_balancer

```hcl
object({
  name_suffix = optional(string, "001")
  name        = optional(string)

  sku      = optional(string, "Standard")  # Basic | Standard | Gateway
  sku_tier = optional(string, "Regional")  # Regional | Global

  frontends = list(object({
    name                          = string
    subnet_id                     = optional(string)  # For internal LB
    private_ip_address_allocation = optional(string)  # Dynamic | Static
    private_ip_address            = optional(string)
    public_ip_address_id          = optional(string)  # For public LB
    zones                         = optional(list(string))
  }))

  public_ip = optional(object({
    enabled           = bool
    name              = optional(string)
    allocation_method = optional(string, "Static")
    sku               = optional(string, "Standard")
    sku_tier          = optional(string, "Regional")
    zones             = optional(list(string))
  }), { enabled = false })
})
```

#### rules

```hcl
list(object({
  name                           = string
  protocol                       = string  # Tcp | Udp | All
  frontend_port                  = number
  backend_port                   = number
  frontend_ip_configuration_name = string

  backend_pool_name       = optional(string)
  probe_name              = optional(string)
  idle_timeout_in_minutes = optional(number)
  load_distribution       = optional(string)
  disable_outbound_snat   = optional(bool)
  floating_ip_enabled     = optional(bool)
  tcp_reset_enabled       = optional(bool)
}))
```

#### nat_rules

```hcl
list(object({
  name                           = string
  protocol                       = string  # Tcp | Udp | All
  frontend_ip_configuration_name = string
  frontend_port                  = optional(number)   # Single port
  frontend_port_start            = optional(number)   # Port range start
  frontend_port_end              = optional(number)   # Port range end
  backend_port                   = number
  backend_pool_name              = optional(string)
}))
```

## Best Practices

1. **Use Standard SKU**: Always use Standard SKU for production workloads
2. **Zone Redundancy**: Configure availability zones for frontend IPs and public IPs
3. **Health Probes**: Use HTTP/HTTPS probes with custom health check endpoints
4. **Outbound Rules**: Disable outbound SNAT on rules if using dedicated outbound rules
5. **TCP Reset**: Enable `tcp_reset_enabled` for better connection handling
6. **Backend Pool Naming**: Use descriptive names that reflect the workload
7. **NAT Rules**: Use port ranges with backend pools for VMSS scenarios

## License

Apache 2.0 Licensed. See LICENSE for full details.

## Authors

Module managed by DNX Solutions.

## Contributing

Please read CONTRIBUTING.md for details on our code of conduct and the process for submitting pull requests.