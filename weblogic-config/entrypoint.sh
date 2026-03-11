#!/bin/bash
###############################################################################
# WebLogic Container Entrypoint Script
# This script creates the domain if it doesn't exist, configures resources,
# then starts WebLogic
###############################################################################

DOMAIN_HOME=/u01/oracle/user_projects/domains/${DOMAIN_NAME:-coolstore_domain}
ADMIN_USER=${ADMIN_USERNAME:-weblogic}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-welcome1}
ADMIN_PORT=${ADMIN_PORT:-7001}
RESOURCES_CONFIGURED_FLAG="$DOMAIN_HOME/.resources_configured"

echo "==============================================="
echo "WebLogic Container Startup"
echo "==============================================="
echo "Domain Name: ${DOMAIN_NAME:-coolstore_domain}"
echo "Domain Home: $DOMAIN_HOME"
echo "Admin User: $ADMIN_USER"
echo "==============================================="

# Check if domain already exists
if [ -d "$DOMAIN_HOME" ]; then
    # If domain exists but resources weren't configured successfully, delete and recreate
    if [ ! -f "$RESOURCES_CONFIGURED_FLAG" ]; then
        echo "Domain exists but resources not configured. Removing domain for clean setup..."
        rm -rf "$DOMAIN_HOME"
        echo "Domain removed. Creating new domain..."
        /u01/oracle/oracle_common/common/bin/wlst.sh /u01/config/create-domain.py

        if [ $? -eq 0 ]; then
            echo "Domain created successfully!"
        else
            echo "ERROR: Failed to create domain"
            exit 1
        fi
    else
        echo "Domain already exists at $DOMAIN_HOME with resources configured"
    fi
else
    echo "Domain not found. Creating new domain..."

    # Create domain using WLST (offline mode)
    /u01/oracle/oracle_common/common/bin/wlst.sh /u01/config/create-domain.py

    if [ $? -eq 0 ]; then
        echo "Domain created successfully!"
    else
        echo "ERROR: Failed to create domain"
        exit 1
    fi
fi

# Copy H2 JDBC driver to domain lib so the datasource can use it
echo "Installing H2 JDBC driver..."
mkdir -p $DOMAIN_HOME/lib
H2_JAR=$(find /u01/app -name 'h2-*.jar' -path '*/WEB-INF/lib/*' 2>/dev/null | head -1)
if [ -n "$H2_JAR" ]; then
    cp -f "$H2_JAR" $DOMAIN_HOME/lib/
    echo "H2 driver copied from WAR: $H2_JAR"
else
    echo "H2 driver will be loaded from application WEB-INF/lib"
fi
mkdir -p /u01/data
echo "H2 database directory: /u01/data"

# Start WebLogic Admin Server in background
echo ""
echo "Starting WebLogic Admin Server..."
echo ""

cd $DOMAIN_HOME

# Start server in background
nohup ./startWebLogic.sh > /u01/oracle/user_projects/weblogic.log 2>&1 &
SERVER_PID=$!

echo "WebLogic starting with PID: $SERVER_PID"
echo "Waiting for server to be ready..."

# Wait for server to start
MAX_WAIT=180
COUNTER=0
while [ $COUNTER -lt $MAX_WAIT ]; do
    if grep -q "Server state changed to RUNNING" /u01/oracle/user_projects/weblogic.log 2>/dev/null; then
        echo "WebLogic Admin Server is RUNNING!"
        break
    fi
    echo -n "."
    sleep 5
    COUNTER=$((COUNTER + 5))
done

if [ $COUNTER -ge $MAX_WAIT ]; then
    echo "ERROR: Server did not start within ${MAX_WAIT} seconds"
    cat /u01/oracle/user_projects/weblogic.log
    exit 1
fi

# Configure resources if not already done
if [ ! -f "$RESOURCES_CONFIGURED_FLAG" ]; then
    echo ""
    echo "Configuring WebLogic resources (JDBC, JMS)..."

    sleep 10  # Give server a moment to fully initialize

    /u01/oracle/oracle_common/common/bin/wlst.sh /u01/config/configure-resources.py

    if [ $? -eq 0 ]; then
        echo "Resources configured successfully!"
        touch "$RESOURCES_CONFIGURED_FLAG"
    else
        echo "WARNING: Failed to configure resources"
        echo "You may need to configure them manually"
    fi
else
    echo "Resources already configured (skipping)"
fi

# Deploy the application
APP_WAR="/u01/app/ROOT.war"
if [ -f "$APP_WAR" ]; then
    echo ""
    echo "Deploying application..."
    /u01/oracle/oracle_common/common/bin/wlst.sh /u01/config/deploy-app.py

    if [ $? -eq 0 ]; then
        echo "Application deployed successfully!"
    else
        echo "WARNING: Application deployment failed"
    fi
else
    echo "WARNING: WAR file not found at $APP_WAR - skipping deployment"
fi

echo ""
echo "==============================================="
echo "WebLogic Admin Server Ready!"
echo "==============================================="
echo "Admin Console: http://localhost:${ADMIN_PORT}/console"
echo "Application:   http://localhost:${ADMIN_PORT}/"
echo "Products API:  http://localhost:${ADMIN_PORT}/services/products"
echo "Username: $ADMIN_USER"
echo "Password: [configured]"
echo "==============================================="

# Tail the log to keep container running
tail -f /u01/oracle/user_projects/weblogic.log
