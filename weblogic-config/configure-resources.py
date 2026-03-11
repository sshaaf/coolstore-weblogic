#!/usr/bin/env python
"""
WebLogic Resource Configuration Script
This script connects to a running WebLogic server and configures resources
Must be run AFTER the server is started
"""

import os
import sys

# Configuration
admin_url = os.environ.get('ADMIN_URL', 't3://localhost:8080')
admin_username = os.environ.get('ADMIN_USERNAME', 'weblogic')
admin_password = os.environ.get('ADMIN_PASSWORD', 'welcome1')

print('========================================')
print('Configuring WebLogic Resources')
print('========================================')
print('Admin URL: ' + admin_url)
print('')

try:
    try:
        # Connect to running server
        print('Connecting to WebLogic Server...')
        connect(admin_username, admin_password, admin_url)
        print('Connected successfully!')
        print('')

        # Start edit session
        print('Starting edit session...')
        edit()
        startEdit()

        # H2 Embedded JDBC DataSource
        print('Creating JDBC DataSource (H2 embedded)...')
        cd('/')

        cmo.createJDBCSystemResource('CoolstoreDS')

        cd('/JDBCSystemResources/CoolstoreDS/JDBCResource/CoolstoreDS')
        cmo.setName('CoolstoreDS')

        cd('/JDBCSystemResources/CoolstoreDS/JDBCResource/CoolstoreDS/JDBCDataSourceParams/CoolstoreDS')
        cmo.setJNDINames(['jdbc/CoolstoreDS'])
        cmo.setGlobalTransactionsProtocol('EmulateTwoPhaseCommit')

        cd('/JDBCSystemResources/CoolstoreDS/JDBCResource/CoolstoreDS/JDBCDriverParams/CoolstoreDS')
        cmo.setUrl('jdbc:h2:file:/u01/data/coolstoredb;AUTO_SERVER=TRUE')
        cmo.setDriverName('org.h2.Driver')
        cmo.setPassword('sa')

        cd('/JDBCSystemResources/CoolstoreDS/JDBCResource/CoolstoreDS/JDBCDriverParams/CoolstoreDS/Properties/CoolstoreDS')
        cmo.createProperty('user')
        cd('/JDBCSystemResources/CoolstoreDS/JDBCResource/CoolstoreDS/JDBCDriverParams/CoolstoreDS/Properties/CoolstoreDS/Properties/user')
        cmo.setValue('sa')

        cd('/JDBCSystemResources/CoolstoreDS/JDBCResource/CoolstoreDS/JDBCConnectionPoolParams/CoolstoreDS')
        cmo.setInitialCapacity(5)
        cmo.setMaxCapacity(50)
        cmo.setMinCapacity(5)
        cmo.setTestTableName('SQL SELECT 1')
        cmo.setTestConnectionsOnReserve(true)
        cmo.setSecondsToTrustAnIdlePoolConnection(10)

        cd('/JDBCSystemResources/CoolstoreDS')
        cmo.addTarget(getMBean('/Servers/AdminServer'))

        print('  DataSource created: jdbc/CoolstoreDS (H2 embedded)')

        # Create JMS Server
        print('Creating JMS Server...')
        cd('/')
        cmo.createJMSServer('CoolstoreJMSServer')

        cd('/JMSServers/CoolstoreJMSServer')
        cmo.addTarget(getMBean('/Servers/AdminServer'))

        print('  JMS Server created')

        # Create JMS Module
        print('Creating JMS System Module...')
        cd('/')
        cmo.createJMSSystemResource('CoolstoreJMSModule')

        cd('/JMSSystemResources/CoolstoreJMSModule')
        cmo.addTarget(getMBean('/Servers/AdminServer'))

        cd('/JMSSystemResources/CoolstoreJMSModule')
        cmo.createSubDeployment('CoolstoreJMSSubDeployment')

        cd('/JMSSystemResources/CoolstoreJMSModule/SubDeployments/CoolstoreJMSSubDeployment')
        cmo.addTarget(getMBean('/JMSServers/CoolstoreJMSServer'))

        print('  JMS Module created')

        # Create Topic
        # Note: Using default weblogic.jms.ConnectionFactory (no need to create)
        print('Creating JMS Topic...')
        cd('/JMSSystemResources/CoolstoreJMSModule/JMSResource/CoolstoreJMSModule')
        cmo.createTopic('OrdersTopic')

        cd('/JMSSystemResources/CoolstoreJMSModule/JMSResource/CoolstoreJMSModule/Topics/OrdersTopic')
        cmo.setJNDIName('jms/topic/orders')
        cmo.setSubDeploymentName('CoolstoreJMSSubDeployment')

        print('  JMS Topic created: jms/topic/orders')

        # Save and activate
        # Note: Work Manager not needed for basic application functionality
        print('')
        print('Saving configuration...')
        save()
        activate()

        print('')
        print('========================================')
        print('Resource Configuration Complete!')
        print('========================================')
        print('')
        print('Resources Created:')
        print('  - JDBC DataSource: jdbc/CoolstoreDS (H2 embedded)')
        print('  - JMS Server: CoolstoreJMSServer')
        print('  - JMS Topic: jms/topic/orders')
        print('')
        print('Using default WebLogic connection factory: weblogic.jms.ConnectionFactory')
        print('')

    except Exception, e:
        print('')
        print('========================================')
        print('ERROR: Resource configuration failed')
        print('========================================')
        print(str(e))
        dumpStack()
        cancelEdit('y')
        sys.exit(1)
finally:
    disconnect()
