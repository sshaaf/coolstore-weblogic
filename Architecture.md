# CoolStore Monolith — Architecture

## Overview

CoolStore is a Java EE 7 e-commerce monolith deployed on Oracle WebLogic Server 12.2.1.4. It exposes a REST API consumed by an AngularJS/PatternFly single-page application. All business logic, messaging, and persistence run inside a single WAR deployed to one WebLogic Admin Server.

---

## Technology Stack

| Layer | Technology |
|---|---|
| Runtime | Oracle WebLogic Server 12.2.1.4 |
| Language | Java 8, Java EE 7 |
| Build | Maven 3.x → `ROOT.war` |
| Persistence | JPA (EclipseLink 2.6, built-in to WebLogic) |
| Database | H2 1.4.200 (embedded, file-backed) |
| JAX-RS | Jersey 2.x (built-in to WebLogic) |
| Messaging | WebLogic JMS |
| Frontend | AngularJS + PatternFly |
| CDI | Weld (built-in to WebLogic) |

---

## Package Structure

```
com.redhat.coolstore
├── model/          — JPA entities and domain DTOs
├── persistence/    — CDI producers (EntityManager, Logger)
├── rest/           — JAX-RS endpoints
├── service/        — EJB business logic and MDBs
└── utils/          — JSON transformers, CDI producers, startup listener
```

---

## Application Layers

### REST Layer (`com.redhat.coolstore.rest`)

All endpoints are mounted under `/services/`.

| Class | Path | Methods | Notes |
|---|---|---|---|
| `RestApplication` | `/services` | — | JAX-RS `Application` config |
| `ProductEndpoint` | `/services/products` | `GET` | Lists catalog products |
| `CartEndpoint` | `/services/cart/{cartId}` | `GET`, `POST`, `DELETE` | `@SessionScoped`; manages cart lifecycle |
| `OrderEndpoint` | `/services/orders` | `GET` | Lists persisted orders |

`CartEndpoint` is `@SessionScoped` so each HTTP session maintains its own cart reference.

### Service Layer (`com.redhat.coolstore.service`)

| Class | EJB Type | Responsibility |
|---|---|---|
| `CatalogService` | `@Stateless` | JPA queries against `PRODUCT_CATALOG` and inventory tables |
| `ProductService` | `@Stateless` | Translates `CatalogItemEntity` to `Product` DTO |
| `ShoppingCartService` | `@Stateful` | Holds cart state per session; orchestrates pricing, promotions, shipping |
| `ShippingService` | `@Stateless @Remote` | Calculates shipping cost and insurance by cart total thresholds |
| `PromoService` | `@ApplicationScoped` | Applies item-level and shipping-level promotions (hard-coded rule set) |
| `OrderService` | `@Stateless` | Persists `Order` entities via JPA |
| `ShoppingCartOrderProcessor` | `@Stateless` | JMS producer — serialises cart to JSON and publishes to `orders` topic |
| `OrderServiceMDB` | `@MessageDriven` | JMS consumer — deserialises order, saves it, updates inventory |
| `InventoryNotificationMDB` | `@MessageDriven` | JMS consumer — checks inventory thresholds, logs supplier warnings |

### Model Layer (`com.redhat.coolstore.model`)

| Class | Type | Notes |
|---|---|---|
| `CatalogItemEntity` | JPA `@Entity` | `PRODUCT_CATALOG` table; 1:1 with `InventoryEntity` |
| `InventoryEntity` | JPA `@Entity` | Tracks stock quantity |
| `Product` | DTO | Flattened view of `CatalogItemEntity` for the REST API |
| `ShoppingCart` | POJO | Aggregates `ShoppingCartItem` list, totals, and savings fields |
| `ShoppingCartItem` | POJO | Line item: product, price, quantity, promo savings |
| `Order` / `OrderItem` | JPA entities | Persisted after checkout |
| `Promotion` | POJO | Item ID + percent-off discount |

---

## Data Flow

### Browsing Products

```
Browser → GET /services/products
       → ProductEndpoint
       → ProductService.getProducts()
       → CatalogService.getCatalogItems()  [JPA → H2]
       → Transformers.toProduct()
       ← JSON list of products
```

### Add to Cart and Checkout

```
Browser → POST /services/cart/{cartId}/{itemId}/{qty}
        → CartEndpoint.add()
        → ShoppingCartService
            → ProductService (fetch product)
            → PromoService.applyCartItemPromotions()
            → ShippingService (JNDI: ejb/ShippingService)
        ← Updated ShoppingCart JSON

Browser → POST /services/cart/checkout/{cartId}
        → CartEndpoint.checkout()
        → ShoppingCartService.checkOutShoppingCart()
        → ShoppingCartOrderProcessor.process()
            → JMS publish to jms/topic/orders (JSON-encoded order)
        ← Empty cart JSON
```

### Order Processing (Async via JMS)

```
JMS Topic: jms/topic/orders
    ├── OrderServiceMDB.onMessage()
    │       → Transformers.jsonToOrder()
    │       → OrderService.save()           [JPA → H2]
    │       → CatalogService.updateInventoryItems()  [JPA → H2]
    │
    └── InventoryNotificationMDB.onMessage()
            → Checks if inventory < 50 (LOW_THRESHOLD)
            → Logs supplier warning if below threshold
```

---

## WebLogic Resources

Configured via WLST Python scripts at container startup:

| Resource | Type | JNDI Name | Details |
|---|---|---|---|
| `CoolstoreDS` | JDBC DataSource | `jdbc/CoolstoreDS` | H2 file DB at `/u01/data/coolstoredb`; pool 5–50 connections |
| `CoolstoreJMSServer` | JMS Server | — | Targeted to AdminServer |
| `CoolstoreJMSModule` | JMS Module | — | Contains the topic |
| `OrdersTopic` | JMS Topic | `jms/topic/orders` | Used by both MDBs and the order processor |
| Connection Factory | (WebLogic default) | `weblogic.jms.ConnectionFactory` | No custom factory needed |

---

## Promotion Rules

`PromoService` (application-scoped, in-memory) implements two rules:

- **Item promotion**: item `329299` gets 25% off.
- **Shipping promotion**: orders with item total ≥ $75 receive free shipping.

Rules are hard-coded. No database or external configuration is involved.

**Shipping tiers** (calculated by `ShippingService`):

| Cart Total | Shipping Cost |
|---|---|
| $0 – $25 | $2.99 |
| $25 – $50 | $4.99 |
| $50 – $75 | $6.99 |
| $75 – $100 | $8.99 |
| $100 – $10,000 | $10.99 |

Orders ≥ $25 also add a shipping insurance charge (2%, 1.5%, or 1% depending on total).

---

## Frontend

The UI lives in `src/main/webapp/app/`:

- **AngularJS** SPA with PatternFly CSS.
- `app.js` — module and routing.
- `controllers/controllers.js` — view logic.
- `directives/header.js` — shared header component.
- Product images bundled as static assets.
- `keycloak.json` present for optional SSO integration (Keycloak realm config in `realm-export.json`).

---

## Container and Deployment

### Local Development (Podman Compose)

```
podman-compose up
```

- WebLogic image: `container-registry.oracle.com/middleware/weblogic:12.2.1.4-dev`
- Port `8080` exposed for admin console and application.
- Named volumes: `weblogic_domain` (domain persistence), `h2_data` (database files).
- Memory: 2–4 GB.

### Container Startup Sequence (`entrypoint.sh`)

1. **Create domain** — `create-domain.py` (WLST offline mode) if domain does not exist.
2. **Start AdminServer** — `startWebLogic.sh` in background; waits up to 180 s for `RUNNING` state.
3. **Configure resources** — `configure-resources.py` (WLST online) — JDBC and JMS; writes a flag file to skip on subsequent starts.
4. **Deploy WAR** — `deploy-app.py` deploys `ROOT.war`.
5. **Tail logs** — keeps the container alive.

### OpenShift Deployment (`deploy-openshift.sh`)

| Resource | Name | Details |
|---|---|---|
| Secret | `coolstore-credentials` | WebLogic admin username and password |
| Deployment | `coolstore` | Single replica, 2–4 GB memory, readiness/liveness probes |
| Service | `coolstore` | ClusterIP on port 8080 |
| Route | `coolstore` | TLS edge termination, HTTPS redirect |

Use `--registry` flag to push to an external registry (e.g., Quay) instead of the OpenShift internal registry.

---

## Exception Handling Practices

### Current Patterns

The application has no centralised exception handling. Each layer handles (or propagates) errors differently:

**REST layer — unchecked propagation**

`CartEndpoint` declares `throws Exception` on mutation methods (`add`, `set`, `delete`). When `ShoppingCartService.priceShoppingCart` throws, the endpoint re-throws the raw exception after rolling back the cart item:

```java
// CartEndpoint.java
try {
    shoppingCartService.priceShoppingCart(cart);
    cart.setShoppingCartItemList(dedupeCartItems(...));
} catch (Exception ex) {
    cart.removeShoppingCartItem(sci);
    throw ex;   // propagates as HTTP 500 with no structured body
}
```

There is no `@ExceptionMapper` or `Response` wrapper, so any unhandled exception becomes an unstructured HTTP 500 response.

**Service layer — checked exceptions wrapped as `RuntimeException`**

JNDI lookup failures in `ShoppingCartService` and JMS failures in `OrderServiceMDB` are caught and re-thrown as unchecked exceptions, letting the EJB container handle transaction rollback:

```java
// ShoppingCartService.java
} catch (NamingException e) {
    throw new RuntimeException(e);  // triggers EJB TX rollback
}

// OrderServiceMDB.java
} catch (JMSException e) {
    throw new RuntimeException(e);  // triggers MDB redelivery by JMS provider
}
```

**MDB layer — swallowed JMS exception**

`InventoryNotificationMDB` catches `JMSException` and prints to `System.err` without re-throwing, which suppresses MDB redelivery:

```java
// InventoryNotificationMDB.java
} catch (JMSException jmse) {
    System.err.println("An exception occurred: " + jmse.getMessage());
    // exception is swallowed — message will NOT be redelivered
}
```

**Data layer — silent null propagation**

`Transformers.toProduct` logs a warning when inventory is null but returns a partial `Product` object. Callers receive a product with zero quantity and no location rather than an error signal:

```java
// Transformers.java
} else {
    log.warning("Inventory for " + entity.getName() + " unknown and missing");
    // prod.quantity stays 0, prod.location/link stay null
}
```

### Logging

Logging is inconsistent across the codebase:

| Location | Mechanism | Level used |
|---|---|---|
| `CatalogService`, `ShoppingCartService`, `ShoppingCartOrderProcessor` | CDI-injected `java.util.logging.Logger` | `INFO` |
| `Transformers` | Static `java.util.logging.Logger` | `WARNING` |
| `OrderServiceMDB` | `System.out.println` | — |
| `InventoryNotificationMDB` | `System.out.println` / `System.err.println` | — |
| `StartupListener` | CDI-injected `Logger` | `INFO` |

MDB classes use `System.out`/`System.err` directly instead of the injected logger used elsewhere in the service layer.

### Known Gaps

| Gap | Location | Impact |
|---|---|---|
| No JAX-RS `ExceptionMapper` | REST layer | Unhandled exceptions return raw HTTP 500 with a WebLogic stack trace body |
| `JMSException` swallowed | `InventoryNotificationMDB` | Failed inventory checks are lost; no redelivery, no dead-letter handling |
| `throws Exception` on REST methods | `CartEndpoint` | Overly broad contract; any downstream failure leaks as an untyped 500 |
| Null inventory silently ignored | `Transformers.toProduct` | Callers cannot distinguish "product has zero stock" from "inventory data missing" |
| No JNDI lookup retry | `ShoppingCartService` | A transient JNDI failure aborts the checkout with no fallback |

---

## Key Design Characteristics

- **Single-process monolith**: all services, REST endpoints, JMS consumers, and the database run in one JVM inside a single WebLogic Admin Server.
- **Stateful session cart**: `ShoppingCartService` is a `@Stateful` EJB; cart state lives in the EJB container tied to the HTTP session.
- **Async order processing via JMS**: checkout is decoupled from order persistence — the cart endpoint returns immediately after publishing to the topic.
- **Embedded database**: H2 in file mode eliminates an external database dependency; the file is stored in a named volume for persistence across container restarts.
- **No external auth dependency at runtime**: Keycloak integration files are present but the application does not enforce authentication at the REST layer — auth is optional/configurable.
