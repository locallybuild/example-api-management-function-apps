```
ooooo                                      oooo  oooo              
`888'                                      `888  `888              
 888          .ooooo.   .ooooo.   .oooo.    888   888  oooo    ooo 
 888         d88' `88b d88' `"Y8 `P  )88b   888   888   `88.  .8'
 888         888   888 888        .oP"888   888   888    `88..8'
 888       o 888   888 888   .o8 d8(  888   888   888     `888'
o888ooooood8 `Y8bod8P' `Y8bod8P' `Y888""8o o888o o888o     .8'
                                                       .o..P'
                                                       `Y8P'
```

# Example: Front two Function Apps with API Management within Locally

This example shows how to publish two Function Apps through one Azure API Management instance on [Locally Build](https://locally.build). Callers use a single gateway with a single subscription key. API Management routes each request to the right app, enforces a rate limit and adds the app's function key. The apps don't accept calls without that key, so callers can't go around the gateway.

```
                                API Management (Developer)
                             ┌───────────────────────────────────────────┐
 curl / browser ─────────▶   │  subscription key check (Shop product)    │
   Ocp-Apim-Subscription-Key │  rate-limit: 20 calls / 60s per key       │
                             │                                           │
                             │  /catalog/*  ── set-header x-functions-key│ ──▶ catalog Function App
                             │                  {{catalog-function-key}} │       GET /api/products
                             │                                           │       GET /api/products/{id}
                             │  /orders/*   ── set-header x-functions-key│ ──▶ orders Function App
                             │                  {{orders-function-key}}  │       GET  /api/orders
                             └───────────────────────────────────────────┘       POST /api/orders
```

The two apps live in [`functions/`](./functions), written in JavaScript with the Node.js v4 programming model:

* **catalog** - `GET /api/products` lists the products on sale, and `GET /api/products/{id}` returns one of them.
* **orders** - `POST /api/orders` places an order (`{"productId": "mug", "quantity": 2}`), and `GET /api/orders` lists the orders placed so far.

Every function uses `authLevel: "function"`, so a request without a function key gets a `401` from the app itself. Each response includes `via`, which says whether the request came through the gateway or went to the app directly.

### What API Management is configured with

| Resource | What it does |
| --- | --- |
| `azurerm_api_management` | The gateway itself, on the Developer SKU |
| `azurerm_api_management_api` (x2) | One API per app, at the paths `/catalog` and `/orders`. Each API's `service_url` is its app's `/api` base URL |
| `azurerm_api_management_api_operation` (x4) | One per function. The gateway only routes requests that match an operation, and returns `404` for anything else without calling the app |
| `azurerm_api_management_named_value` (x2) | Each app's default function key, stored as a **secret** |
| `azurerm_api_management_api_policy` (x2) | Adds the app's function key as `x-functions-key`, plus an `x-forwarded-by` header |
| `azurerm_api_management_product` | **Shop**, which contains both APIs and requires a subscription |
| `azurerm_api_management_product_policy` | `rate-limit`: 20 calls per 60 seconds for each subscription |
| `azurerm_api_management_subscription` | A key scoped to the Shop product, so one key opens both APIs |

The gateway strips the API's path and appends the rest of the URL to `service_url`, so:

| Gateway request | Forwarded to |
| --- | --- |
| `GET  <gateway>/catalog/products` | `GET  <catalog app>/api/products` |
| `GET  <gateway>/catalog/products/mug` | `GET  <catalog app>/api/products/mug` |
| `POST <gateway>/orders/orders` | `POST <orders app>/api/orders` |

### Function keys

Terraform reads each app's default function key with the `azurerm_function_app_host_keys` data source and stores it in a secret named value. The API policy refers to the key by name:

```xml
<set-header name="x-functions-key" exists-action="override">
  <value>{{catalog-function-key}}</value>
</set-header>
```

The gateway fills in the value for each request. As a result, the key never appears in the policy XML, the callers never see it, and they only need their subscription key.

### Identity

Neither app connects to anything except its host storage (`AzureWebJobsStorage`). Both apps run as a single **user-assigned managed identity** that holds `Storage Blob Data Owner` and `Storage Queue Data Contributor` on the Storage Account. Shared-key access is switched off on the account (`shared_access_key_enabled = false`). The two apps share the Storage Account, and each host keeps its state under its own host ID.

## Requirements

* [Locally Build](https://locally.build). Using API Management needs the Standard plan or above.
* Either [HashiCorp Terraform](https://terraform.io) or [OpenTofu](https://opentofu.org).
* Either [Docker](https://www.docker.com) or [Podman](https://podman.io) (recommended).
* [Node.js](https://nodejs.org) 24, to install the functions' dependencies. Locally runs the functions with the Node.js on your machine, so its major version needs to match the Function Apps' `node_version`.
* [jq](https://jqlang.org), which some of the commands below use to read Terraform's JSON outputs.
* The Locally Plugin for `Microsoft.ApiManagement` installed (`locally plugin install --name Microsoft.ApiManagement`).
* The Locally Plugin for `Microsoft.Insights` installed (`locally plugin install --name Microsoft.Insights`).
* The Locally Plugin for `Microsoft.OperationalInsights` installed (`locally plugin install --name Microsoft.OperationalInsights`).
* The Locally Plugin for `Microsoft.Storage` installed (`locally plugin install --name Microsoft.Storage`).
* The Locally Plugin for `Microsoft.Web` installed (`locally plugin install --name Microsoft.Web`).

## Running the example

First up, we need to ensure our container runtime (Docker or Podman) is running, then launch Locally:

```bash
locally build
```

Each Function App is deployed from a zip that Terraform builds from its directory under `functions/`. The zips have to include the apps' dependencies, so we first install those:

```bash
(cd functions/catalog && npm install)
(cd functions/orders && npm install)
```

With Locally running, in another terminal we can initialise Terraform, which both downloads the providers we need and configures the module for use:

```bash
cd environments/locally
terraform init
```

> [!NOTE]
> You can use OpenTofu instead by running `tofu` wherever this says `terraform`.

With Terraform initialised, we can then provision the example by running:

```bash
locally run terraform apply
```

A single apply creates everything: the two Function Apps with their code, the API Management instance, its APIs, operations, policies and product, and a subscription. When it finishes, the URLs are in the outputs:

```
gateway_url  = "https://locally-example-apimfunc-apim.switchboard.locally:5670"
products_url = "https://locally-example-apimfunc-apim.switchboard.locally:5670/catalog/products"
orders_url   = "https://locally-example-apimfunc-apim.switchboard.locally:5670/orders/orders"
```

The subscription key is a sensitive output. Read it into a variable, along with the two URLs:

```bash
KEY=$(locally run terraform output -raw subscription_key)
PRODUCTS=$(locally run terraform output -raw products_url)
ORDERS=$(locally run terraform output -raw orders_url)
```

Then call both apps through the gateway:

```bash
curl -H "Ocp-Apim-Subscription-Key: $KEY" "$PRODUCTS"
curl -H "Ocp-Apim-Subscription-Key: $KEY" "$PRODUCTS/mug"

curl -H "Ocp-Apim-Subscription-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"productId": "mug", "quantity": 2}' "$ORDERS"
curl -H "Ocp-Apim-Subscription-Key: $KEY" "$ORDERS"
```

Each response says `"via": "locally-example-apimfunc-apim"`, which shows the request came through the gateway.

### What the gateway refuses

```bash
# No subscription key: 401 from API Management
curl -i "$PRODUCTS"

# A method or path with no matching operation: 404 from API Management
curl -i -X DELETE -H "Ocp-Apim-Subscription-Key: $KEY" "$ORDERS"

# Going around the gateway: 401 from the Function App, which wants a function key
curl -i "$(locally run terraform output -json function_app_urls | jq -r .catalog)/products"

# More than 20 calls in a minute: 429 from API Management, with a Retry-After header
for i in $(seq 1 25); do
  curl -s -o /dev/null -w "%{http_code}\n" -H "Ocp-Apim-Subscription-Key: $KEY" "$PRODUCTS"
done
```

---

As this Terraform configuration sends the functions' logs into a Log Analytics Workspace, we can then query them within [the Locally Dashboard, in the Monitoring section](https://localhost:5678/monitoring/components), by running:

```
FunctionAppLogs | order by TimeGenerated desc
```

## Notes

The orders app keeps orders in memory, so they're lost when its worker restarts. This keeps the example focused on API Management and the two apps behind it. A real app would store orders in a database.

Every policy keeps `<base />` in each section, so the product's rate limit (the outer scope) runs before the API's `set-header`s. Locally runs the `inbound` section only, which is all this example uses: `outbound` and `backend` policies aren't applied yet.

API Management also has `azurerm_api_management_backend` entities, with `credentials` that can add a header such as `x-functions-key`. This example uses `service_url` and a `set-header` policy instead. Both approaches work on Azure and within Locally: [`example-api-management-backends`](https://github.com/locallybuild/example-api-management-backends) fronts Function Apps and a Web App with backends, the way Azure's "import from Function App" sets them up.

The rate limit is set by the `rate_limit_calls` and `rate_limit_period` variables on the module.

Terraform writes each package to `.build/<app>-<hash>.zip`, where the hash covers everything in that app's directory. The provider only redeploys the code when `zip_deploy_file` changes, so the hash in the name is what makes an edit to the code (or an `npm install`) reach the app on the next apply.

## Tearing it down

```bash
cd environments/locally
locally run terraform destroy
```
