@description('Environment name (dev, staging, prod)')
param environment string

@description('Azure region for resources')
param location string

@description('Project name used in resource naming')
param projectName string

@description('Tags to apply to all resources')
param tags object

@description('PostgreSQL administrator login')
@secure()
param administratorLogin string

@description('PostgreSQL administrator password')
@secure()
param administratorPassword string

var serverName = '${projectName}-pg-${environment}'
var databaseName = 'hearhere'

var skuName = environment == 'prod' ? 'Standard_D2ds_v5' : 'Standard_B1ms'
var skuTier = environment == 'prod' ? 'GeneralPurpose' : 'Burstable'
var storageSizeGB = environment == 'prod' ? 128 : 32
var backupRetentionDays = environment == 'prod' ? 35 : 7

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: '16'
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    storage: {
      storageSizeGB: storageSizeGB
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: environment == 'prod' ? 'Enabled' : 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Enabled'
    }
  }
}

resource allowAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: postgresServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: postgresServer
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource postGISExtension 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: postgresServer
  name: 'azure.extensions'
  properties: {
    value: 'POSTGIS'
    source: 'user-override'
  }
}

@description('PostgreSQL server resource ID')
output id string = postgresServer.id

@description('PostgreSQL server FQDN')
output fqdn string = postgresServer.properties.fullyQualifiedDomainName

@description('Database name')
output databaseName string = databaseName

@description('PostgreSQL server name')
output serverName string = postgresServer.name
