// PlaceOrder and ListOrders - the orders app's two endpoints.
//
//   POST /api/orders  places an order: {"productId": "...", "quantity": n}
//   GET  /api/orders  lists the orders placed so far, newest first
//
// Both use authLevel "function": a caller needs one of the app's function keys,
// so the app can't be called around API Management. The gateway holds the key
// and adds it to each request it forwards (see 4-api-management.tf).
//
// Orders are kept in memory, so they last as long as the worker process does.
// That keeps the example to API Management and the two apps behind it; a real
// app would write them to a database.

const { randomUUID } = require("node:crypto");
const { app } = require("@azure/functions");

const MAX_QUANTITY = 100;
const orders = [];

// Set by API Management on the requests it forwards, so the response shows
// which way the request came in.
function via(request) {
    return request.headers.get("x-forwarded-by") || "direct";
}

app.http("PlaceOrder", {
    route: "orders",
    methods: ["POST"],
    authLevel: "function",
    handler: async (request, context) => {
        const body = await request.json().catch(() => null);
        const productId = String((body && body.productId) || "").trim();
        const quantity = Number((body && body.quantity) ?? 1);

        if (!productId) {
            return { status: 400, jsonBody: { error: "productId is required" } };
        }
        if (!Number.isInteger(quantity) || quantity < 1 || quantity > MAX_QUANTITY) {
            return { status: 400, jsonBody: { error: `quantity must be a whole number from 1 to ${MAX_QUANTITY}` } };
        }

        const order = { id: randomUUID(), productId, quantity, placedAt: new Date().toISOString() };
        orders.unshift(order);
        context.log(`PlaceOrder: order ${order.id} for ${quantity} x ${productId} (via ${via(request)})`);
        return { status: 201, jsonBody: { app: "orders", via: via(request), order } };
    },
});

app.http("ListOrders", {
    route: "orders",
    methods: ["GET"],
    authLevel: "function",
    handler: async (request) => {
        return { jsonBody: { app: "orders", via: via(request), count: orders.length, orders } };
    },
});
