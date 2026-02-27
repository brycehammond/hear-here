@description('Environment name (dev, staging, prod)')
param environment string

@description('Azure region for resources')
param location string

@description('Project name used in resource naming')
param projectName string

@description('Tags to apply to all resources')
param tags object

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('Key Vault URI')
param keyVaultUri string

@description('PostgreSQL server FQDN')
param postgresqlFqdn string

@description('PostgreSQL database name')
param postgresqlDatabaseName string

@description('Storage account name for Functions host storage')
param storageAccountName string

@description('Storage account blob endpoint')
param storageBlobEndpoint string

@description('Service Bus fully qualified namespace')
param serviceBusNamespace string

@description('Storage account resource ID for role assignment')
param storageAccountId string

@description('Service Bus namespace resource ID for role assignment')
param serviceBusId string

var functionAppName = '${projectName}-func-${environment}'
var hostingPlanName = '${projectName}-func-plan-${environment}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true // Linux
  }
  kind: 'functionapp'
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNET-ISOLATED|10.0'
      appSettings: [
        // Identity-based connection for Functions host storage (no account keys)
        { name: 'AzureWebJobsStorage__accountName', value: storageAccountName }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'dotnet-isolated' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
        { name: 'KeyVault__Uri', value: keyVaultUri }
        { name: 'Database__Host', value: postgresqlFqdn }
        { name: 'Database__Name', value: postgresqlDatabaseName }
        { name: 'Storage__BlobEndpoint', value: storageBlobEndpoint }
        { name: 'ServiceBus__Namespace', value: serviceBusNamespace }
      ]
    }
  }
}

// Storage Blob Data Owner: b7e6dc6d-f1e8-4753-8033-0f276bb0955b
// (superset of Contributor; required for user delegation SAS key generation + Functions host storage)
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'

resource storageBlobOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountId, functionApp.id, storageBlobDataOwnerRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Queue Data Contributor: 974c5e8b-45b9-4653-ba55-5f855dd0fb88
// (required for Functions host internal queue operations)
var storageQueueDataContributorRoleId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'

resource storageQueueRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountId, functionApp.id, storageQueueDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Table Data Contributor: 0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3
// (required for Durable Functions state storage in table storage)
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'

resource storageTableRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountId, functionApp.id, storageTableDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Service Bus Data Sender: 69a216fc-b8fb-44d8-bc22-1f3c2cd27a39
// Service Bus Data Receiver: 4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0
var serviceBusDataSenderRoleId = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
var serviceBusDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'

resource serviceBusNs 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: last(split(serviceBusId, '/'))
}

resource serviceBusSenderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusId, functionApp.id, serviceBusDataSenderRoleId)
  scope: serviceBusNs
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataSenderRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource serviceBusReceiverRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusId, functionApp.id, serviceBusDataReceiverRoleId)
  scope: serviceBusNs
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataReceiverRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Function App resource ID')
output id string = functionApp.id

@description('Function App name')
output name string = functionApp.name

@description('Function App default hostname')
output defaultHostname string = functionApp.properties.defaultHostName

@description('Function App managed identity principal ID')
output principalId string = functionApp.identity.principalId
