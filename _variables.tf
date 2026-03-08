variable "name" {
  description = "Resource name prefix used for all resources in this module."
  type        = string
}

variable "resource_group" {
  description = "Create or use an existing resource group."
  type = object({
    create   = bool
    name     = string
    location = optional(string)
  })
}

variable "tags" {
  description = "Extra tags merged with default tags."
  type        = map(string)
  default     = {}
}

variable "diagnostics" {
  description = "Optional Azure Monitor diagnostic settings."
  type = object({
    enabled                        = optional(bool, false)
    log_analytics_workspace_id     = optional(string)
    storage_account_id             = optional(string)
    eventhub_authorization_rule_id = optional(string)
  })
  default = {}
}

variable "load_balancer" {
  description = "Load Balancer configuration. Supports internal (subnet) and public (public IP) frontends."
  type = object({
    name_suffix = optional(string, "001")
    name        = optional(string)

    sku      = optional(string, "Standard") # Basic | Standard | Gateway
    sku_tier = optional(string, "Regional") # Regional | Global

    edge_zone = optional(string)

    frontends = list(object({
      name = string

      # Internal frontend
      subnet_id                     = optional(string)
      private_ip_address_allocation = optional(string)         # Dynamic | Static
      private_ip_address            = optional(string)
      private_ip_address_version    = optional(string, "IPv4") # IPv4 | IPv6

      # Public frontend
      public_ip_address_id = optional(string)
      public_ip_prefix_id  = optional(string)

      zones = optional(list(string))    
      gateway_load_balancer_frontend_ip_configuration_id = optional(string)
    }))

    # Optional: let module create a Public IP for a public frontend
    public_ip = optional(object({
      enabled           = bool
      name              = optional(string)
      allocation_method = optional(string, "Static")
      sku               = optional(string, "Standard")
      sku_tier          = optional(string, "Regional")
      zones             = optional(list(string))
    }), { enabled = false })
  })
}

variable "backend_pools" {
  description = "Backend address pools."
  type = list(object({
    name               = string
    virtual_network_id = optional(string)
    synchronous_mode   = optional(string) # Automatic | Manual (required when virtual_network_id is set)

    tunnel_interfaces = optional(list(object({
      identifier = number
      type       = string # None | Internal | External
      protocol   = string # None | Native | VXLAN
      port       = number
    })), [])
  }))
  default = []
}

variable "probes" {
  description = "Health probes."
  type = list(object({
    name                = string
    protocol            = optional(string, "Tcp") # Tcp | Http | Https
    port                = number
    request_path        = optional(string)
    interval_in_seconds = optional(number)
    number_of_probes    = optional(number)
    probe_threshold     = optional(number)
  }))
  default = []
}

variable "rules" {
  description = "Load balancing rules."
  type = list(object({
    name                           = string
    protocol                       = string # Tcp | Udp | All
    frontend_port                  = number
    backend_port                   = number
    frontend_ip_configuration_name = string

    backend_pool_name = optional(string)
    backend_pool_ids  = optional(list(string))

    probe_name = optional(string)
    probe_id   = optional(string)

    idle_timeout_in_minutes = optional(number)
    load_distribution       = optional(string)
    disable_outbound_snat   = optional(bool)
    floating_ip_enabled     = optional(bool)
    tcp_reset_enabled       = optional(bool)
  }))
  default = []
}

variable "nat_rules" {
  description = "Inbound NAT rules (NOTE: not supported with VMSS, use lb_nat_pool)."
  type = list(object({
    name                           = string
    protocol                       = string # Tcp | Udp | All
    frontend_ip_configuration_name = string

    # Single port mapping
    frontend_port = optional(number)

    # Or port range mapping (requires backend_address_pool_id)
    frontend_port_start = optional(number)
    frontend_port_end   = optional(number)

    backend_port = number

    backend_pool_name       = optional(string)
    backend_address_pool_id = optional(string)

    idle_timeout_in_minutes = optional(number)
    floating_ip_enabled     = optional(bool)
    tcp_reset_enabled       = optional(bool)
  }))
  default = []
}

variable "backend_pool_associations" {
  description = "Optional NIC -> backend pool associations (for standalone VMs)."
  type = list(object({
    pool_name             = string
    network_interface_id  = string
    ip_configuration_name = string
  }))
  default = []
}