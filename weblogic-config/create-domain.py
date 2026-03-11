#!/usr/bin/env python
"""
WebLogic Domain Creation Script for CoolStore
This script creates a basic WebLogic domain
Resources (DataSource, JMS) are configured after server starts
"""

import os

# Read configuration from environment variables
admin_username = os.environ.get('ADMIN_USERNAME', 'weblogic')
admin_password = os.environ.get('ADMIN_PASSWORD', 'welcome1')
domain_name = os.environ.get('DOMAIN_NAME', 'coolstore_domain')
admin_port = int(os.environ.get('ADMIN_PORT', '8080'))
domain_path = '/u01/oracle/user_projects/domains/' + domain_name

print('========================================')
print('Creating WebLogic Domain: ' + domain_name)
print('========================================')

# Read domain template
readTemplate('/u01/oracle/wlserver/common/templates/wls/wls.jar')

# Configure Admin Server
cd('Servers/AdminServer')
set('ListenAddress', '')
set('ListenPort', admin_port)
set('Name', 'AdminServer')

# Set domain credentials
cd('/')
cd('Security/base_domain/User/weblogic')
cmo.setPassword(admin_password)

# Set domain name
setOption('DomainName', domain_name)

# Set production mode
setOption('ServerStartMode', 'dev')

# Write domain
writeDomain(domain_path)
closeTemplate()

print('')
print('========================================')
print('Domain Created Successfully!')
print('========================================')
print('Domain Home: ' + domain_path)
print('Admin Username: ' + admin_username)
print('Admin Port: ' + str(admin_port))
print('')
print('Note: JDBC and JMS resources will be configured')
print('      after the server starts using online WLST.')
print('========================================')
print('')
