#!/bin/bash
###############################################################################
# Deploy CoolStore to OpenShift
#
# This script builds the container image, pushes it to a registry, and
# deploys the application to an OpenShift cluster.
#
# Prerequisites:
#   - oc CLI logged into an OpenShift cluster
#   - podman
#   - mvn
#   - Access to a container registry (quay.io or OpenShift internal)
#
# Usage:
#   ./deploy-openshift.sh                                  # uses OpenShift internal registry
#   ./deploy-openshift.sh --registry quay.io/<your-org>    # uses Quay
#   ./deploy-openshift.sh --project my-coolstore           # custom namespace
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

APP_NAME="coolstore"
PROJECT="coolstore"
REGISTRY=""
IMAGE_TAG="latest"

while [[ $# -gt 0 ]]; do
    case $1 in
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --project)
            PROJECT="$2"
            shift 2
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --help|-h)
            sed -n '2,15p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo ""
echo -e "${BOLD}${CYAN}Deploy CoolStore to OpenShift${NC}"
echo -e "${CYAN}=============================${NC}"
echo ""

# --- Preflight checks ---

echo -e "${BOLD}Checking prerequisites...${NC}"

if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: oc CLI is not installed${NC}"
    exit 1
fi

if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: not logged into an OpenShift cluster${NC}"
    echo "  Run: oc login <cluster-url>"
    exit 1
fi

if ! command -v podman &> /dev/null; then
    echo -e "${RED}Error: podman is not installed${NC}"
    exit 1
fi

CLUSTER=$(oc whoami --show-server)
USER=$(oc whoami)
echo -e "${GREEN}Cluster:${NC} $CLUSTER"
echo -e "${GREEN}User:${NC}    $USER"
echo ""

# --- Determine registry ---

if [ -z "$REGISTRY" ]; then
    INTERNAL_REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}' 2>/dev/null || true)
    if [ -n "$INTERNAL_REGISTRY" ]; then
        REGISTRY="$INTERNAL_REGISTRY"
        echo -e "${GREEN}Using OpenShift internal registry:${NC} $REGISTRY"
        echo "Logging into internal registry..."
        podman login -u "$USER" -p "$(oc whoami -t)" "$REGISTRY" --tls-verify=false
    else
        echo -e "${RED}Error: no registry specified and OpenShift internal registry route not found${NC}"
        echo ""
        echo "Either expose the internal registry:"
        echo "  oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{\"spec\":{\"defaultRoute\":true}}'"
        echo ""
        echo "Or specify an external registry:"
        echo "  ./deploy-openshift.sh --registry quay.io/<your-org>"
        exit 1
    fi
fi

FULL_IMAGE="${REGISTRY}/${PROJECT}/${APP_NAME}-weblogic:${IMAGE_TAG}"
echo -e "${GREEN}Image:${NC}   $FULL_IMAGE"
echo ""

# --- Build the WAR ---

echo -e "${BOLD}Step 1: Building the application...${NC}"
mvn clean package -q
echo -e "${GREEN}WAR built:${NC} target/ROOT.war"
echo ""

# --- Build the container image ---

echo -e "${BOLD}Step 2: Building container image...${NC}"

CONTAINERFILE=$(mktemp)
cat > "$CONTAINERFILE" <<'EOF'
FROM container-registry.oracle.com/middleware/weblogic:12.2.1.4-dev

COPY weblogic-config/ /u01/config/
COPY target/ROOT.war /u01/app/ROOT.war
COPY target/ROOT/WEB-INF/lib/h2-1.4.200.jar /u01/app/h2-1.4.200.jar

CMD ["/bin/bash", "/u01/config/entrypoint.sh"]
EOF

podman build -t "$FULL_IMAGE" -f "$CONTAINERFILE" .
rm -f "$CONTAINERFILE"

echo -e "${GREEN}Image built:${NC} $FULL_IMAGE"
echo ""

# --- Push to registry ---

echo -e "${BOLD}Step 3: Pushing image to registry...${NC}"
podman push "$FULL_IMAGE" --tls-verify=false
echo -e "${GREEN}Image pushed.${NC}"
echo ""

# --- Create OpenShift resources ---

echo -e "${BOLD}Step 4: Deploying to OpenShift...${NC}"

oc project "$PROJECT" 2>/dev/null || oc new-project "$PROJECT"

oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${APP_NAME}-credentials
  namespace: ${PROJECT}
type: Opaque
stringData:
  ADMIN_USERNAME: weblogic
  ADMIN_PASSWORD: welcome1
EOF

oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${PROJECT}
  labels:
    app: ${APP_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
      containers:
        - name: ${APP_NAME}
          image: ${FULL_IMAGE}
          ports:
            - containerPort: 8080
              protocol: TCP
          env:
            - name: ADMIN_USERNAME
              valueFrom:
                secretKeyRef:
                  name: ${APP_NAME}-credentials
                  key: ADMIN_USERNAME
            - name: ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: ${APP_NAME}-credentials
                  key: ADMIN_PASSWORD
            - name: DOMAIN_NAME
              value: coolstore_domain
            - name: ADMIN_PORT
              value: "8080"
          resources:
            requests:
              memory: "2Gi"
              cpu: "500m"
            limits:
              memory: "4Gi"
              cpu: "2"
          readinessProbe:
            httpGet:
              path: /services/products
              port: 8080
            initialDelaySeconds: 180
            periodSeconds: 15
            timeoutSeconds: 5
          livenessProbe:
            httpGet:
              path: /services/products
              port: 8080
            initialDelaySeconds: 240
            periodSeconds: 30
            timeoutSeconds: 5
EOF

oc apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${PROJECT}
  labels:
    app: ${APP_NAME}
spec:
  selector:
    app: ${APP_NAME}
  ports:
    - name: http
      port: 8080
      targetPort: 8080
      protocol: TCP
EOF

oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ${APP_NAME}
  namespace: ${PROJECT}
  labels:
    app: ${APP_NAME}
spec:
  to:
    kind: Service
    name: ${APP_NAME}
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

echo ""
echo -e "${GREEN}Deployment created. Waiting for rollout...${NC}"
oc rollout status deployment/${APP_NAME} --timeout=600s || true

ROUTE=$(oc get route ${APP_NAME} -o jsonpath='{.spec.host}')

echo ""
echo -e "${BOLD}${CYAN}=============================${NC}"
echo -e "${BOLD}${CYAN} Deployment Complete${NC}"
echo -e "${BOLD}${CYAN}=============================${NC}"
echo ""
echo -e "${BOLD}Application:${NC}   https://${ROUTE}/"
echo -e "${BOLD}Products API:${NC}  https://${ROUTE}/services/products"
echo -e "${BOLD}Admin Console:${NC} https://${ROUTE}/console"
echo ""
echo -e "${BOLD}Useful commands:${NC}"
echo "  oc logs -f deployment/${APP_NAME}      # view logs"
echo "  oc get pods -l app=${APP_NAME}         # check pod status"
echo "  oc delete project ${PROJECT}           # tear down everything"
echo ""
