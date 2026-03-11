#!/usr/bin/env python
"""
Deploy CoolStore Application to WebLogic
"""

import os
import sys

admin_url = os.environ.get('ADMIN_URL', 't3://localhost:7001')
admin_username = os.environ.get('ADMIN_USERNAME', 'weblogic')
admin_password = os.environ.get('ADMIN_PASSWORD', 'welcome1')
app_path = '/u01/app/ROOT.war'
app_name = 'coolstore'

print('========================================')
print('Deploying CoolStore Application')
print('========================================')

try:
    try:
        # Connect to Admin Server
        print('Connecting to WebLogic Server at: ' + admin_url)
        connect(admin_username, admin_password, admin_url)

        # Check if WAR file exists
        if not os.path.exists(app_path):
            print('ERROR: WAR file not found at: ' + app_path)
            print('Please build the application first: mvn clean package')
            sys.exit(1)

        # Check if app is already deployed
        print('Checking deployment status...')
        domainRuntime()
        cd('AppRuntimeStateRuntime/AppRuntimeStateRuntime')
        appStatus = cmo.getCurrentState(app_name, 'AdminServer')

        if appStatus is not None:
            print('Application already deployed, redeploying...')
            serverConfig()
            progress = redeploy(app_name, app_path, targets='AdminServer', upload='true')
            print('Redeploy initiated...')
        else:
            print('Deploying new application...')
            progress = deploy(app_name, app_path, targets='AdminServer', upload='true')
            print('Deploy initiated...')

        # Start application if not running
        print('Starting application...')
        startApplication(app_name)

        print('')
        print('========================================')
        print('Deployment Successful!')
        print('========================================')
        print('')
        print('Application: ' + app_name)
        print('WAR File: ' + app_path)
        print('Target: AdminServer')
        print('')
        print('Access the application at:')
        print('  http://localhost:7001/')
        print('  http://localhost:7001/services/products')
        print('')
        print('Admin Console:')
        print('  http://localhost:7001/console')

    except Exception, e:
        print('')
        print('========================================')
        print('Deployment Failed!')
        print('========================================')
        print(str(e))
        dumpStack()
        sys.exit(1)
finally:
    disconnect()
