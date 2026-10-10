// ListProducts and GetProduct - the catalog's two read-only endpoints.
//
//   GET /api/products       every product
//   GET /api/products/{id}  one product, or 404
//
// Both use authLevel "function": a caller needs one of the app's function keys,
// so the app can't be called around API Management. The gateway holds the key
// and adds it to each request it forwards (see 4-api-management.tf).

const { app } = require("@azure/functions");
const { PRODUCTS } = require("../products");

// Set by API Management on the requests it forwards, so the response shows
// which way the request came in.
function via(request) {
    return request.headers.get("x-forwarded-by") || "direct";
}

app.http("ListProducts", {
    route: "products",
    methods: ["GET"],
    authLevel: "function",
    handler: async (request, context) => {
        context.log(`ListProducts: ${PRODUCTS.length} products (via ${via(request)})`);
        return { jsonBody: { app: "catalog", via: via(request), products: PRODUCTS } };
    },
});

app.http("GetProduct", {
    route: "products/{id}",
    methods: ["GET"],
    authLevel: "function",
    handler: async (request, context) => {
        const product = PRODUCTS.find((p) => p.id === request.params.id);
        if (!product) {
            return { status: 404, jsonBody: { error: `no product with id "${request.params.id}"` } };
        }
        return { jsonBody: { app: "catalog", via: via(request), product } };
    },
});
