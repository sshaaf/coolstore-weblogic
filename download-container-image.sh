#!/bin/bash
###############################################################################
# Download WebLogic Container Image from Oracle Container Registry
#
# Prerequisites:
#   1. A free Oracle account (https://profile.oracle.com/myprofile/account/create-account.jspx)
#   2. An auth token generated at https://cloud.oracle.com
#      (Profile -> User Settings -> Auth Tokens -> Generate Token)
#   3. Accept the WebLogic license at https://container-registry.oracle.com
#      (Sign in -> Search "weblogic" -> middleware/weblogic -> Accept license)
#
# Usage:
#   ./download-container-image.sh
###############################################################################

set -e

WEBLOGIC_IMAGE="container-registry.oracle.com/middleware/weblogic:12.2.1.4-dev"
REGISTRY="container-registry.oracle.com"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}${CYAN}WebLogic Container Image Download${NC}"
echo -e "${CYAN}==================================${NC}"
echo ""

# Check podman is available
if ! command -v podman &> /dev/null; then
    echo -e "${RED}Error: podman is not installed${NC}"
    exit 1
fi

# Check if image already exists locally
if podman image exists "$WEBLOGIC_IMAGE" 2>/dev/null; then
    echo -e "${GREEN}Image already exists locally:${NC}"
    podman images --format "  {{.Repository}}:{{.Tag}}  ({{.Size}}, created {{.Created}})" "$WEBLOGIC_IMAGE"
    echo ""
    read -p "Re-download? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Done. Image is ready to use.${NC}"
        exit 0
    fi
fi

# Check if already logged in
echo -e "${BOLD}Step 1: Oracle Container Registry Login${NC}"
echo ""

if podman manifest inspect "$WEBLOGIC_IMAGE" &> /dev/null; then
    echo -e "${GREEN}Already logged in and have access to WebLogic image.${NC}"
else
    echo "Log in with your Oracle account credentials:"
    echo ""
    echo -e "  ${BOLD}Username:${NC} Your Oracle account email"
    echo -e "  ${BOLD}Password:${NC} Your auth token (NOT your Oracle account password)"
    echo ""
    echo -e "${YELLOW}Don't have an auth token?${NC}"
    echo "  1. Go to ${CYAN}https://cloud.oracle.com${NC}"
    echo "  2. Profile icon -> User Settings -> Auth Tokens"
    echo "  3. Generate Token -> copy it (shown only once)"
    echo ""
    echo -e "${YELLOW}Haven't accepted the WebLogic license?${NC}"
    echo "  1. Go to ${CYAN}https://container-registry.oracle.com${NC}"
    echo "  2. Sign in -> Search 'weblogic' -> middleware/weblogic"
    echo "  3. Click Continue -> Accept the license agreement"
    echo ""

    if ! podman login "$REGISTRY"; then
        echo ""
        echo -e "${RED}Login failed.${NC}"
        echo ""
        echo "Common causes:"
        echo "  - Used Oracle password instead of auth token"
        echo "  - Auth token copied incorrectly or expired"
        echo "  - WebLogic license not accepted at container-registry.oracle.com"
        exit 1
    fi

    echo ""
    echo -e "${GREEN}Login successful.${NC}"

    # Verify image access after login
    if ! podman manifest inspect "$WEBLOGIC_IMAGE" &> /dev/null; then
        echo ""
        echo -e "${RED}Cannot access the WebLogic image.${NC}"
        echo ""
        echo "You need to accept the WebLogic license agreement:"
        echo "  1. Go to ${CYAN}https://container-registry.oracle.com${NC}"
        echo "  2. Sign in -> Search 'weblogic' -> middleware/weblogic"
        echo "  3. Click Continue -> Accept the license agreement"
        echo "  4. Wait 2-3 minutes, then run this script again"
        exit 1
    fi
fi

# Pull the image
echo ""
echo -e "${BOLD}Step 2: Downloading WebLogic Image${NC}"
echo ""
echo "Image: $WEBLOGIC_IMAGE"
echo "Size:  ~1.2 GB (this may take a few minutes)"
echo ""

if podman pull "$WEBLOGIC_IMAGE"; then
    echo ""
    echo -e "${GREEN}${BOLD}Download complete.${NC}"
    echo ""
    podman images --format "  {{.Repository}}:{{.Tag}}  ({{.Size}})" "$WEBLOGIC_IMAGE"
    echo ""
    echo "You can now run the application:"
    echo "  mvn clean package && podman-compose up"
else
    echo ""
    echo -e "${RED}Failed to pull image.${NC}"
    exit 1
fi
