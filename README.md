# Azure Application Gateway Terraform Module

Azure Application Gateway provides HTTP based load balancing that enables in creating routing rules for traffic based on HTTP. Traditional load balancers operate at the transport level and then route the traffic using source IP address and port to deliver data to a destination IP and port. Application Gateway using additional attributes such as URI (Uniform Resource Identifier) path and host headers to route the traffic.

Classic load balances operate at OSI layer 4 - TCP and UDP, while Application Gateway operates at application layer OSI layer 7 for load balancing.

This terraform module quickly creates a desired application gateway with additional options like WAF, Custom Error Configuration, SSL offloading with SSL policies, URL path mapping and many other options.

## Module Usage

```hcl
# Azurerm Provider configuration
provider "azurerm" {
  features {}
}

resource "azurerm_user_assigned_identity" "example" {
  resource_group_name = "rg-shared-westeurope-01"
  location            = "westeurope"
  name                = "appgw-api"
}

module "application-gateway" {
  source  = "kumarvna/application-gateway/azurerm"
  version = "1.0.0"

  # Resource Group and location, VNet and Subnet detials (Required)
  resource_group_name  = "rg-shared-westeurope-01"
  location             = "westeurope"
  virtual_network_name = "vnet-shared-hub-westeurope-001"
  subnet_name          = "snet-appgateway"
  app_gateway_name     = "testgateway"

  # SKU requires `name`, `tier` to use for this Application Gateway
  # `Capacity` property is optional if `autoscale_configuration` is set
  sku = {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  # A backend pool routes request to backend servers, which serve the request.
  # Can create different backend pools for different types of requests
  backend_address_pools = [
    {
      name  = "appgw-testgateway-westeurope-bapool01"
      fqdns = ["example1.com", "example2.com"]
    },
    {
      name         = "appgw-testgateway-westeurope-bapool02"
      ip_addresses = ["1.2.3.4", "2.3.4.5"]
    }
  ]

  # An application gateway routes traffic to the backend servers using the port, protocol, and other settings
  # The port and protocol used to check traffic is encrypted between the application gateway and backend servers
  # List of backend HTTP settings can be added here.  
  # `probe_name` argument is required if you are defing health probes.
  backend_http_settings = [
    {
      name                  = "appgw-testgateway-westeurope-be-http-set1"
      cookie_based_affinity = "Disabled"
      path                  = "/"
      enable_https          = true
      request_timeout       = 30
      probe_name            = "appgw-testgateway-westeurope-probe1" # Remove this if `health_probes` object is not defined.
      connection_draining = {
        enable_connection_draining = true
        drain_timeout_sec          = 300

      }
    },
    {
      name                  = "appgw-testgateway-westeurope-be-http-set2"
      cookie_based_affinity = "Enabled"
      path                  = "/"
      enable_https          = false
      request_timeout       = 30
    }
  ]

  # List of HTTP/HTTPS listeners. SSL Certificate name is required
  # `Basic` - This type of listener listens to a single domain site, where it has a single DNS mapping to the IP address of the 
  # application gateway. This listener configuration is required when you host a single site behind an application gateway.
  # `Multi-site` - This listener configuration is required when you want to configure routing based on host name or domain name for 
  # more than one web application on the same application gateway. Each website can be directed to its own backend pool.
  # Setting `host_name` value changes Listener Type to 'Multi site`. `host_names` allows special wildcard charcters.
  http_listeners = [
    {
      name                 = "appgw-testgateway-westeurope-be-htln01"
      ssl_certificate_name = "appgw-testgateway-westeurope-ssl01"
      host_name            = null
    }
  ]

  # Request routing rule is to determine how to route traffic on the listener. 
  # The rule binds the listener, the back-end server pool, and the backend HTTP settings.
  # `Basic` - All requests on the associated listener (for example, blog.contoso.com/*) are forwarded to the associated 
  # backend pool by using the associated HTTP setting.
  # `Path-based` - This routing rule lets you route the requests on the associated listener to a specific backend pool, 
  # based on the URL in the request. 
  request_routing_rules = [
    {
      name                       = "appgw-testgateway-westeurope-be-rqrt"
      rule_type                  = "Basic"
      http_listener_name         = "appgw-testgateway-westeurope-be-htln01"
      backend_address_pool_name  = "appgw-testgateway-westeurope-bapool01"
      backend_http_settings_name = "appgw-testgateway-westeurope-be-http-set1"
    }
  ]

  # TLS termination (previously known as Secure Sockets Layer (SSL) Offloading)
  # The certificate on the listener requires the entire certificate chain (PFX certificate) to be uploaded to establish the chain of trust.
  # Authentication and trusted root certificate setup are not required for trusted Azure services such as Azure App Service.
  ssl_certificates = [{
    name     = "appgw-testgateway-westeurope-ssl01"
    data     = "./keyBag.pfx"
    password = "P@$$w0rd123"
  }]

  # By default, an application gateway monitors the health of all resources in its backend pool and automatically removes unhealthy ones. 
  # It then monitors unhealthy instances and adds them back to the healthy backend pool when they become available and respond to health probes.
  # must allow incoming Internet traffic on TCP ports 65503-65534 for the Application Gateway v1 SKU, and TCP ports 65200-65535 
  # for the v2 SKU with the destination subnet as Any and source as GatewayManager service tag. This port range is required for Azure infrastructure communication.
  # Additionally, outbound Internet connectivity can't be blocked, and inbound traffic coming from the AzureLoadBalancer tag must be allowed.
  health_probes = [
    {
      name                = "appgw-testgateway-westeurope-probe1"
      host                = "127.0.0.1"
      interval            = 30
      path                = "/"
      port                = 443
      timeout             = 30
      unhealthy_threshold = 3
    }
  ]

  # A list with a single user managed identity id to be assigned to access Keyvault
  identity_ids = ["${azurerm_user_assigned_identity.example.id}"]

  # (Optional) To enable Azure Monitoring for Azure Application Gateway
  # (Optional) Specify `storage_account_name` to save monitoring logs to storage. 
  log_analytics_workspace_name = "loganalytics-we-sharedtest2"

  # Adding TAG's to Azure resources
  tags = {
    ProjectName  = "demo-internal"
    Env          = "dev"
    Owner        = "user@example.com"
    BusinessUnit = "CORP"
    ServiceClass = "Gold"
  }
}
```

## Advanced Usage of the Module

### `ssl_policy` - Application Gateway TLS policy

Application Gateway has three predefined security policies. You can configure your gateway with any of these policies to get the appropriate level of security. The policy names are annotated by the year and month in which they were configured. If not specified, Defaults to `AppGwSslPolicy20150501`.

Policy Name |Min. Protocol Version
--------|----------------------------
`AppGwSslPolicy20150501`|TLSv1_0 
`AppGwSslPolicy20170401`|TLSv1_1 
`AppGwSslPolicy20170401S`|TLSv1_2

```hcl
module "application-gateway" {
  source  = "kumarvna/application-gateway/azurerm"
  version = "1.1.0"

  # .... omitted

  ssl_policy = {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20170401S"
  }

  # .... omitted
}
```

### `custom_error_configuration` - Create Application Gateway custom error pages

Application Gateway allows you to create custom error pages instead of displaying default error pages. You can use your own branding and layout using a custom error page.

Custom error pages are supported for the following two scenarios:

* **Maintenance page** - This custom error page is sent instead of a 502 bad gateway page. It's shown when Application Gateway has no backend to route traffic to.
* **Unauthorized access page** - This custom error page is sent instead of a 403 unauthorized access page. It's shown when the Application Gateway WAF detects malicious traffic and blocks it.

Custom error pages can be defined at the global level and the listener level:

* **Global level** - the error page applies to traffic for all the web applications deployed on that application gateway.
* **Listener level** - the error page is applied to traffic received on that listener.
* **Both** - the custom error page defined at the listener level overrides the one set at global level.

> The size of the error page must be less than 1 MB. You may reference either internal or external images/CSS for this HTML file. For externally referenced resources, use absolute URLs that are publicly accessible.

```hcl
module "application-gateway" {
  source  = "kumarvna/application-gateway/azurerm"
  version = "1.1.0"

  # .... omitted

  http_listeners = [
    {
      name                 = "appgw-testgateway-westeurope-be-htln01"
      ssl_certificate_name = "appgw-testgateway-westeurope-ssl01"
      host_name            = null

      /*       custom_error_configuration = [
        {
          custom_error_page_url = "https://example.blob.core.windows.net/appgateway/custom_error_403_page.html"
          status_code           = "HttpStatus403"
        },
        {
          custom_error_page_url = "https://example.blob.core.windows.net/appgateway/custom_error_502_page.html"
          status_code           = "HttpStatus502"
        }
      ] */
    }
  ]

  custom_error_configuration = [
    {
      custom_error_page_url = "https://example.blob.core.windows.net/appgateway/custom_error_403_page.html"
      status_code           = "HttpStatus403"
    },
    {
      custom_error_page_url = "https://example.blob.core.windows.net/appgateway/custom_error_502_page.html"
      status_code           = "HttpStatus502"
    }
  ]

  # .... omitted
}
```

### `url_path_maps` - URL Path Based Routing

URL Path Based Routing allows you to route traffic to back-end server pools based on URL Paths of the request. One of the scenarios is to route requests for different content types to different backend server pools.

> For both the v1 and v2 SKUs, rules are processed in the order they are listed in the portal. If a basic listener is listed first and matches an incoming request, it gets processed by that listener. However, it is highly recommended to configure multi-site listeners first prior to configuring a basic listener. This ensures that traffic gets routed to the right back end.

The `url_path_maps` is used to specify Path patterns to back-end server pool mappings. The following code example is the snippet of `url_path_maps` from example file.

```hcl
module "application-gateway" {
  source  = "kumarvna/application-gateway/azurerm"
  version = "1.1.0"

  # .... omitted

  url_path_maps = [
    {
      name                               = "testgateway-url-path"
      default_backend_address_pool_name  = "appgw-testgateway-westeurope-bapool01"
      default_backend_http_settings_name = "appgw-testgateway-westeurope-be-http-set1"
      path_rules = [
        {
          name                       = "api"
          paths                      = ["/api/*"]
          backend_address_pool_name  = "appgw-testgateway-westeurope-bapool01"
          backend_http_settings_name = "appgw-testgateway-westeurope-be-http-set1"
        },
        {
          name                       = "videos"
          paths                      = ["/videos/*"]
          backend_address_pool_name  = "appgw-testgateway-westeurope-bapool02"
          backend_http_settings_name = "appgw-testgateway-westeurope-be-http-set2"
        }
      ]
    }
  ]

  # .... omitted
}
```

### `health_probes` - Application Gateway health monitoring

By default, an application gateway monitors the health of all resources in its backend pool and automatically removes unhealthy ones.  It then monitors unhealthy instances and adds them back to the healthy backend pool when they become available and respond to health probes.

You must allow incoming Internet traffic on `TCP` ports `65503-65534` for the Application Gateway `v1 SKU`, and TCP ports `65200-65535` for the `v2 SKU` with the destination subnet as `Any` and source as `GatewayManager` service tag. This port range is required for Azure infrastructure communication.

Additionally, outbound Internet connectivity can't be blocked, and inbound traffic coming from the `AzureLoadBalancer` tag must be allowed.

You can specify a list of health probes to monitor application gateway health. The following code example is the snippet of `health_probes` from example file.

```hcl
module "application-gateway" {
  source  = "kumarvna/application-gateway/azurerm"
  version = "1.1.0"

  # .... omitted

  health_probes = [
    {
      name                = "appgw-testgateway-westeurope-probe1"
      host                = "127.0.0.1"
      interval            = 30
      path                = "/"
      port                = 443
      timeout             = 30
      unhealthy_threshold = 3
    }
  ]

  # .... omitted
}
```

### `redirect_configuration` -  redirect traffic 

You can use application gateway to redirect traffic. It has a generic redirection mechanism which allows for redirecting traffic received at one listener to another listener or to an external site. A common redirection scenario for many web applications is to support automatic HTTP to HTTPS redirection to ensure all communication between application and its users occurs over an encrypted path.

The following types of redirection are supported:

* 301 Permanent Redirect
* 302 Found
* 303 See Other
* 307 Temporary Redirect

Application Gateway redirection support offers the following capabilities:

* **Global redirection**: Redirects from one listener to another listener on the gateway. This enables HTTP to HTTPS redirection on a site.

* **Path-based redirection**: This type of redirection enables HTTP to HTTPS redirection only on a specific site area, for example a shopping cart area denoted by /cart/*.

### `rewrite_rule_set` - Rewrite HTTP headers and URL's

Application Gateway allows you to rewrite selected content of requests and responses. With this feature, you can translate URLs, query string parameters as well as modify request and response headers. It also allows you to add conditions to ensure that the URL or the specified headers are rewritten only when certain conditions are met. These conditions are based on the request and response information.

> HTTP header and URL rewrite features are only available for the Application Gateway v2 SKU

For more informaiton check [Microsoft documentation](https://docs.microsoft.com/en-us/azure/application-gateway/rewrite-http-headers-url). 

### `waf_configuration` - Azure Web Application Firewall

Azure Web Application Firewall (WAF) on Azure Application Gateway provides centralized protection of your web applications from common exploits and vulnerabilities. Web applications are increasingly targeted by malicious attacks that exploit commonly known vulnerabilities. SQL injection and cross-site scripting are among the most common attacks.

The `waf_configuration` object is used to specify waf configuration, disabled rule groups and exclusions. The following code example is the snippet of `waf_configuration` from example file.

```hcl
module "application-gateway" {
  source  = "kumarvna/application-gateway/azurerm"
  version = "1.1.0"

  # .... omitted

  waf_configuration = {
    firewall_mode            = "Detection"
    rule_set_version         = "3.1"
    file_upload_limit_mb     = 100
    max_request_body_size_kb = 128

    disabled_rule_group = [
      {
        rule_group_name = "REQUEST-930-APPLICATION-ATTACK-LFI"
        rules           = ["930100", "930110"]
      },
      {
        rule_group_name = "REQUEST-920-PROTOCOL-ENFORCEMENT"
        rules           = ["920160"]
      }
    ]

    exclusion = [
      {
        match_variable          = "RequestCookieNames"
        selector                = "SomeCookie"
        selector_match_operator = "Equals"
      },
      {
        match_variable          = "RequestHeaderNames"
        selector                = "referer"
        selector_match_operator = "Equals"
      }
    ]
  }

  # .... omitted
}
```

For more information on Web Application Firewall CRS rule groups and rules, [visit Microsoft documentation](https://docs.microsoft.com/en-us/azure/web-application-firewall/ag/application-gateway-crs-rulegroups-rules?tabs=owasp32).

## Recommended naming and tagging conventions

Applying tags to your Azure resources, resource groups, and subscriptions to logically organize them into a taxonomy. Each tag consists of a name and a value pair. For example, you can apply the name `Environment` and the value `Production` to all the resources in production.
For recommendations on how to implement a tagging strategy, see Resource naming and tagging decision guide.

>**Important** :
Tag names are case-insensitive for operations. A tag with a tag name, regardless of the casing, is updated or retrieved. However, the resource provider might keep the casing you provide for the tag name. You'll see that casing in cost reports. **Tag values are case-sensitive.**

An effective naming convention assembles resource names by using important resource information as parts of a resource's name. For example, using these [recommended naming conventions](https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/naming-and-tagging#example-names), a public IP resource for a production SharePoint workload is named like this: `pip-sharepoint-prod-westus-001`.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 0.13 |
| azurerm | >= 2.59.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | >= 2.59.0 |

## Inputs

Name | Description | Type | Default
---- | ----------- | ---- | -------
`resource_group_name`|The name of an existing resource group.|string|`""`
`location`|The location for all resources while creating a new resource group.|string|`""`
`virtual_network_name`|The name of the virtual network|string|`""`
`subnet_name`|The name of the subnet to use in VM scale set|string|`""`
`app_gateway_name`|The name of the application gateway|string|`""`
`log_analytics_workspace_name`|The name of log analytics workspace name|string|`null`
`storage_account_name`|The name of the hub storage account to store logs|string|`null`
domain_name_label|Label for the Domain Name. Will be used to make up the FQDN|string|`null`
`enable_http2`|Is HTTP2 enabled on the application gateway resource?|string|`false`
`zones`|A collection of availability zones to spread the Application Gateway over|list(string)|`[]`
`firewall_policy_id`|The ID of the Web Application Firewall Policy which can be associated with app gateway|string|`null`
`sku`|The sku pricing model of v1 and v2|object({})|`{}`
`autoscale_configuration`|Minimum or Maximum capacity for autoscaling. Accepted values are for Minimum in the range `0` to `100` and for Maximum in the range `2` to `125`|object|`null`
`private_ip_address`|Private IP Address to assign to the Load Balancer|string|`null`
`backend_address_pools`|List of backend address pools|list(object{})|`[]`
backend_http_settings|List of backend HTTP settings|list(object{})|`[]`
`http_listeners`|List of HTTP/HTTPS listeners. SSL Certificate name is required|list(object{})|`[]`
`request_routing_rules`|List of Request routing rules to be used for listeners|list(object{})|`[]`
`identity_ids`|Specifies a list with a single user managed identity id to be assigned to the Application Gateway|list(string)|`null`
`authentication_certificates`|Authentication certificates to allow the backend with Azure Application Gateway|list(object{})|`[]`
`trusted_root_certificates`|Trusted root certificates to allow the backend with Azure Application Gateway|list(object{})|`[]`
`ssl_policy`|Application Gateway SSL configuration|object({})|`null`
`ssl_certificates`|List of SSL certificates data for Application gateway|list(object{})|`[]`
`health_probes`|List of Health probes used to test backend pools health|list(object{})|`[]`
`url_path_maps`|List of URL path maps associated to path-based rules|list(object{})|`[]`
`redirect_configuration`|list of maps for redirect configurations|list(map(string))|`[]`
`custom_error_configuration`|Global level custom error configuration for application gateway|list(map(string))|`[]`
`rewrite_rule_set`|List of rewrite rule set including rewrite rules|any|`[]`
`waf_configuration`|Web Application Firewall support for your Azure Application Gateway|object({})|`null`
`Tags`|A map of tags to add to all resources|map|`{}`

## Outputs

Name | Description
---- | -----------
`application_gateway_id`|The ID of the Application Gateway
`authentication_certificate_id`|The ID of the Authentication Certificate
`backend_address_pool_id`|The ID of the Backend Address Pool
`backend_http_settings_id`|The ID of the Backend HTTP Settings Configuration
`backend_http_settings_probe_id`|The ID of the Backend HTTP Settings Configuration associated Probe
`frontend_ip_configuration_id`|The ID of the Frontend IP Configuration
`frontend_port_id`|The ID of the Frontend Port
`gateway_ip_configuration_id`|The ID of the Gateway IP Configuration
`http_listener_id`|The ID of the HTTP Listener
`http_listener_frontend_ip_configuration_id`|The ID of the associated Frontend Configuration
`http_listener_frontend_port_id`|The ID of the associated Frontend Port
`http_listener_ssl_certificate_id`|The ID of the associated SSL Certificate
`probe_id`|The ID of the health Probe
`request_routing_rule_id`|The ID of the Request Routing Rule
`request_routing_rule_http_listener_id`|The ID of the Request Routing Rule associated HTTP Listener
`request_routing_rule_backend_address_pool_id`|The ID of the Request Routing Rule associated Backend Address Pool
`request_routing_rule_backend_http_settings_id`|The ID of the Request Routing Rule associated Backend HTTP Settings Configuration
`request_routing_rule_redirect_configuration_id`|The ID of the Request Routing Rule associated Redirect Configuration
`request_routing_rule_rewrite_rule_set_id`|The ID of the Request Routing Rule associated Rewrite Rule Set
`request_routing_rule_url_path_map_id`|The ID of the Request Routing Rule associated URL Path Map
`ssl_certificate_id`|The ID of the SSL Certificate
`ssl_certificate_public_cert_data`|The Public Certificate Data associated with the SSL Certificate
`url_path_map_id`|The ID of the URL Path Map
`url_path_map_default_backend_address_pool_id`|The ID of the Default Backend Address Pool associated with URL Path Map
`url_path_map_default_backend_http_settings_id`|The ID of the Default Backend HTTP Settings Collection associated with URL Path Map
`url_path_map_default_redirect_configuration_id`|The ID of the Default Redirect Configuration associated with URL Path Map
`url_path_map_path_rule_id`|The ID of the Path Rule associated with URL Path Map
`url_path_map_path_rule_backend_address_pool_id`|The ID of the Backend Address Pool used in this Path Rule
`url_path_map_path_rule_backend_http_settings_id`|The ID of the Backend HTTP Settings Collection used in this Path Rule
`url_path_map_path_rule_redirect_configuration_id`|The ID of the Redirect Configuration used in this Path Rule
`url_path_map_path_rule_rewrite_rule_set_id`|The ID of the Rewrite Rule Set used in this Path Rule
`custom_error_configuration_id`|The ID of the Custom Error Configuration
`redirect_configuration_id`|The ID of the Redirect Configuration
`rewrite_rule_set_id`|The ID of the Rewrite Rule Set

## Resource Graph

![](graph.png)

## Authors

Originally created by [Kumaraswamy Vithanala](mailto:kumarvna@gmail.com)

## Other resources

* [Azure Application Gateway documentation](https://docs.microsoft.com/en-us/azure/application-gateway/)

* [Terraform AzureRM Provider Documentation](https://www.terraform.io/docs/providers/azurerm/index.html)
