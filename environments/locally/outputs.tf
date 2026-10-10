output "gateway_url" {
  description = "The API Management gateway's base URL."
  value       = module.api-management-function-apps.gateway_url
}

output "products_url" {
  description = "Lists the products, through the gateway (GET). Append /<id> for one product."
  value       = module.api-management-function-apps.products_url
}

output "orders_url" {
  description = "Lists (GET) and places (POST) orders, through the gateway."
  value       = module.api-management-function-apps.orders_url
}

output "subscription_key" {
  description = "The Shop subscription's primary key, sent as the Ocp-Apim-Subscription-Key header."
  value       = module.api-management-function-apps.subscription_key
  sensitive   = true
}

output "function_app_urls" {
  description = "Each Function App's own URL, which refuses calls that don't carry a function key."
  value       = module.api-management-function-apps.function_app_urls
}

output "api_management_name" {
  description = "The name of the API Management instance."
  value       = module.api-management-function-apps.api_management_name
}
