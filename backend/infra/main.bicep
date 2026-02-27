@description('Environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Project name used in resource naming')
param projectName string = 'hearhere'

@description('PostgreSQL administrator login')
@secure()
param postgresAdminLogin string

@description('PostgreSQL administrator password')
@secure()
param postgresAdminPassword string

var tags = {
  project: 'hear-here'
  environment: environment
}

// ---------- Foundation resources (no dependencies) ----------

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-${environment}'
  params: {
    environment: environment
    location: location
    projectName: projectName
    tags: tags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage-${environment}'
  params: {
    environment: environment
    location: location
    projectName: projectName
    tags: tags
  }
}

module serviceBus 'modules/servicebus.bicep' = {
  name: 'servicebus-${environment}'
  params: {
    environment: environment
    location: location
    projectName: projectName
    tags: tags
  }
}

module database 'modules/database.bicep' = {
  name: 'database-${environment}'
  params: {
    environment: environment
    location: location
    projectName: projectName
    tags: tags
    administratorLogin: postgresAdminLogin
    administratorPassword: postgresAdminPassword
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-${environment}'
  params: {
    environment: environment
    location: location
    projectName: projectName
    tags: tags
  }
}

// ---------- Compute resources (depend on foundation) ----------

module api 'modules/api.bicep' = {
  name: 'api-${environment}'
  params: {
    environment: environment
    location: location
    projectName: projectName
    tags: tags
    appInsightsConnectionString: monitoring.outputs.connectionString
    keyVaultUri: keyVault.outputs.uri
    postgresqlFqdn: database.outputs.fqdn
    postgresqlDatabaseName: database.outputs.databaseName
    storageBlobEndpoint: storage.outputs.blobEndpoint
    serviceBusNamespace: serviceBus.outputs.fullyQualifiedNamespace
    storageAccountId: storage.outputs.id
    serviceBusId: serviceBus.outputs.id
  }
}

module functions 'modules/functions.bicep' = {
  name: 'functions-${environment}'
  params: {
    environment: environment
    location: location
    projectName: projectName
    tags: tags
    appInsightsConnectionString: monitoring.outputs.connectionString
    keyVaultUri: keyVault.outputs.uri
    postgresqlFqdn: database.outputs.fqdn
    postgresqlDatabaseName: database.outputs.databaseName
    storageAccountName: storage.outputs.name
    storageBlobEndpoint: storage.outputs.blobEndpoint
    serviceBusNamespace: serviceBus.outputs.fullyQualifiedNamespace
    storageAccountId: storage.outputs.id
    serviceBusId: serviceBus.outputs.id
  }
}

// ---------- Key Vault role assignments (depend on compute) ----------

module keyVaultAccess 'modules/keyvault-access.bicep' = {
  name: 'keyvault-access-${environment}'
  params: {
    keyVaultName: keyVault.outputs.name
    principalIds: [
      api.outputs.principalId
      functions.outputs.principalId
    ]
  }
}

// ---------- Outputs ----------

output apiUrl string = 'https://${api.outputs.defaultHostname}'
output functionsUrl string = 'https://${functions.outputs.defaultHostname}'
output keyVaultUri string = keyVault.outputs.uri
output postgresqlFqdn string = database.outputs.fqdn
output storageAccountName string = storage.outputs.name
output serviceBusNamespace string = serviceBus.outputs.fullyQualifiedNamespace
