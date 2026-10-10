# ---------------------------------------------------------------------------
# API Management - the one front door for both Function Apps.
#
# Callers send every request to the gateway with a subscription key. The
# gateway picks the API by the first path segment (/catalog or /orders),
# checks the key and the product's rate limit, adds that app's function key,
# and forwards the request to the Function App.
# ---------------------------------------------------------------------------
resource "azurerm_api_management" "main" {
  name                = "${var.name_prefix}-apim"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = "Developer_1"
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Named values - each app's default function key, stored as a secret so it
# isn't shown in the portal or returned by a plain GET. Policies refer to it as
# {{<app>-function-key}}, and the gateway substitutes the value per request.
# ---------------------------------------------------------------------------
resource "azurerm_api_management_named_value" "function_key" {
  for_each = local.function_apps

  name                = "${each.key}-function-key"
  display_name        = "${each.key}-function-key"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  value               = data.azurerm_function_app_host_keys.main[each.key].default_function_key
  secret              = true
}

# ---------------------------------------------------------------------------
# One API per Function App.
#
# The gateway strips the API's path and appends the rest to service_url, so
#   GET  <gateway>/catalog/products/mug  ->  <catalog app>/api/products/mug
#   POST <gateway>/orders/orders         ->  <orders app>/api/orders
# ---------------------------------------------------------------------------
resource "azurerm_api_management_api" "main" {
  for_each = local.function_apps

  name                  = each.key
  display_name          = title(each.key)
  path                  = each.key
  protocols             = ["https"]
  revision              = "1"
  service_url           = "https://${azurerm_linux_function_app.main[each.key].default_hostname}/api"
  subscription_required = true
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azurerm_api_management.main.name
}

# ---------------------------------------------------------------------------
# Operations - the gateway routes only requests that match one of an API's
# operations, so each function is declared here with its method and route.
# Anything else gets a 404 from the gateway without reaching the app.
# ---------------------------------------------------------------------------
locals {
  operations = {
    "catalog-list-products" = { api = "catalog", method = "GET", url_template = "/products", display_name = "List products" }
    "catalog-get-product"   = { api = "catalog", method = "GET", url_template = "/products/{id}", display_name = "Get a product", params = ["id"] }
    "orders-list-orders"    = { api = "orders", method = "GET", url_template = "/orders", display_name = "List orders" }
    "orders-place-order"    = { api = "orders", method = "POST", url_template = "/orders", display_name = "Place an order" }
  }
}

resource "azurerm_api_management_api_operation" "main" {
  for_each = local.operations

  operation_id        = each.key
  api_name            = azurerm_api_management_api.main[each.value.api].name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = each.value.display_name
  method              = each.value.method
  url_template        = each.value.url_template

  dynamic "template_parameter" {
    for_each = lookup(each.value, "params", [])
    content {
      name     = template_parameter.value
      type     = "string"
      required = true
    }
  }
}

# ---------------------------------------------------------------------------
# API policies - add the app's function key to each request the gateway
# forwards, and mark the request as having come through the gateway (the apps
# echo this back as "via", so you can see the path a request took).
# ---------------------------------------------------------------------------
resource "azurerm_api_management_api_policy" "main" {
  for_each = local.function_apps

  api_name            = azurerm_api_management_api.main[each.key].name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = <<-XML
    <policies>
      <inbound>
        <base />
        <set-header name="x-functions-key" exists-action="override">
          <value>{{${azurerm_api_management_named_value.function_key[each.key].display_name}}}</value>
        </set-header>
        <set-header name="x-forwarded-by" exists-action="override">
          <value>${azurerm_api_management.main.name}</value>
        </set-header>
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
  XML
}

# ---------------------------------------------------------------------------
# Product - groups the two APIs into one offering that a subscription grants
# access to, and applies a rate limit to every subscription to it.
# ---------------------------------------------------------------------------
resource "azurerm_api_management_product" "shop" {
  product_id            = "shop"
  display_name          = "Shop"
  description           = "The catalog and orders APIs."
  api_management_name   = azurerm_api_management.main.name
  resource_group_name   = azurerm_resource_group.main.name
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product_api" "shop" {
  for_each = local.function_apps

  api_name            = azurerm_api_management_api.main[each.key].name
  product_id          = azurerm_api_management_product.shop.product_id
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
}

# The limit is counted per subscription: each key gets its own allowance, and
# a key that goes over it gets a 429 with a Retry-After header.
resource "azurerm_api_management_product_policy" "shop" {
  product_id          = azurerm_api_management_product.shop.product_id
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = <<-XML
    <policies>
      <inbound>
        <base />
        <rate-limit calls="${var.rate_limit_calls}" renewal-period="${var.rate_limit_period}" />
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
  XML
}

# ---------------------------------------------------------------------------
# Subscription - the key callers send in the Ocp-Apim-Subscription-Key
# header. It's scoped to the Shop product, so it opens both APIs and is
# subject to the product's rate limit.
# ---------------------------------------------------------------------------
resource "azurerm_api_management_subscription" "shop" {
  display_name        = "Shop example"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  product_id          = azurerm_api_management_product.shop.id
  state               = "active"
}
