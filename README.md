# CoolStore Monolith

A Java EE 7 e-commerce application deployed on Oracle WebLogic Server 12.2.1.4. Uses an embedded H2 database — no external database required.

## Prerequisites

- Java 8 (JDK)
- Maven 3.x
- Podman (with a running machine) and podman-compose

## Download the WebLogic Container Image

The application runs on Oracle WebLogic Server. The container image must be pulled from Oracle Container Registry, which requires a free Oracle account and an auth token.

A helper script is provided to handle login and download:

```bash
./download-container-image.sh
```

The script will prompt for your Oracle credentials. Use your **auth token** as the password (not your Oracle account password).

To generate an auth token:

1. Sign in at https://cloud.oracle.com
2. Click your profile icon (top-right) and select **User Settings**
3. Under **Auth Tokens**, click **Generate Token**
4. Copy the token immediately — it is only shown once

You also need to accept the WebLogic license (one-time):

1. Go to https://container-registry.oracle.com
2. Sign in, search for `weblogic`
3. Click **middleware/weblogic**, then **Continue** and accept the license

## Project Structure

```
├── pom.xml                     # Maven build (produces ROOT.war)
├── docker-compose.yml          # Podman/Docker compose for local dev
├── weblogic-config/            # WebLogic domain and resource setup scripts
│   ├── create-domain.py        # WLST: creates the WebLogic domain
│   ├── configure-resources.py  # WLST: configures JDBC (H2) and JMS resources
│   ├── deploy-app.py           # WLST: deploys the WAR to the server
│   └── entrypoint.sh           # Container entrypoint (orchestrates all of the above)
└── src/
    ├── main/java/              # Application source code
    ├── main/resources/
    │   └── META-INF/
    │       ├── persistence.xml # JPA config (EclipseLink + H2)
    │       └── import.sql      # Seed data loaded on startup
    └── main/webapp/            # Web frontend + deployment descriptors
```

## Build

```bash
mvn clean package
```

This produces `target/ROOT.war`.

## Run Locally with Podman

### Start

```bash
mvn clean package && podman-compose up
```

First startup takes approximately 5 minutes (domain creation, resource configuration, app deployment). Subsequent starts are faster because the domain is persisted in a named volume.

Once you see `WebLogic Admin Server Ready!` in the logs, the application is available at:

| URL | Description |
|---|---|
| http://localhost:8080/ | Web storefront |
| http://localhost:8080/services/products | Products REST API |
| http://localhost:8080/services/cart/{cartId} | Shopping cart API |
| http://localhost:8080/services/orders | Orders REST API |
| http://localhost:8080/console | WebLogic Admin Console |

Admin console credentials: `weblogic` / `welcome1`

### Stop

```bash
podman-compose down
```

### Full Reset

Wipe the WebLogic domain and H2 database to start completely fresh:

```bash
podman-compose down
podman pod rm -af && podman rm -af
podman volume rm coolstore_weblogic_domain coolstore_h2_data
```

### View Logs

```bash
podman logs -f coolstore-weblogic
```

## Build a Container Image

Create a self-contained image with the WAR baked in:

```bash
mvn clean package

podman build -t coolstore-weblogic:latest -f Containerfile .
```

Using this `Containerfile`:

```dockerfile
FROM container-registry.oracle.com/middleware/weblogic:12.2.1.4-dev

COPY weblogic-config/ /u01/config/
COPY target/ROOT.war /u01/app/ROOT.war
COPY target/ROOT/WEB-INF/lib/h2-1.4.200.jar /u01/app/h2-1.4.200.jar

CMD ["/bin/bash", "/u01/config/entrypoint.sh"]
```

Run the built image standalone (no compose needed):

```bash
podman run -d --name coolstore \
  -p 8080:8080 \
  -e ADMIN_USERNAME=weblogic \
  -e ADMIN_PASSWORD=welcome1 \
  -e DOMAIN_NAME=coolstore_domain \
  coolstore-weblogic:latest
```

## Push to a Private Quay Repository

Tag and push the image to your Quay registry:

```bash
# Log in to Quay (once)
podman login quay.io

# Tag the image
podman tag coolstore-weblogic:latest quay.io/<your-org>/coolstore-weblogic:latest

# Push
podman push quay.io/<your-org>/coolstore-weblogic:latest
```

To use a specific version tag:

```bash
podman tag coolstore-weblogic:latest quay.io/<your-org>/coolstore-weblogic:1.0.0
podman push quay.io/<your-org>/coolstore-weblogic:1.0.0
```

Pulling from the private repo on another machine:

```bash
podman login quay.io
podman pull quay.io/<your-org>/coolstore-weblogic:latest
```

## REST API Examples

```bash
# List all products
curl http://localhost:8080/services/products

# Get shopping cart
curl http://localhost:8080/services/cart/123

# Add an item to cart (itemId=329299, quantity=1)
curl -X POST http://localhost:8080/services/cart/123/329299/1

# Checkout
curl -X POST http://localhost:8080/services/cart/checkout/123

# List orders
curl http://localhost:8080/services/orders
```

## Technology Stack

| Component | Technology |
|---|---|
| Runtime | Oracle WebLogic Server 12.2.1.4 |
| Language | Java 8, Java EE 7 |
| JPA Provider | EclipseLink 2.6 (WebLogic built-in) |
| Database | H2 1.4.200 (embedded) |
| JAX-RS | Jersey 2.x (WebLogic built-in) |
| Messaging | WebLogic JMS |
| Frontend | AngularJS + PatternFly |
