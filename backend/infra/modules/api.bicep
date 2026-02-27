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

@description('Storage account blob endpoint')
param storageBlobEndpoint string

@description('Service Bus fully qualified namespace')
param serviceBusNamespace string

@description('Storage account resource ID for role assignment')
param storageAccountId string

@description('Service Bus namespace resource ID for role assignment')
param serviceBusId string

var appServicePlanName = '${projectName}-plan-${environment}'
var webAppName = '${projectName}-api-${environment}'
var appServiceSku = environment == 'prod' ? 'S1' : 'B1'

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: appServiceSku
  }
  properties: {
    reserved: true // Linux
  }
  kind: 'linux'
}

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      alwaysOn: environment == 'prod'
      minTlsVersion: '1.2'
      appSettings: [
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
// (superset of Contributor; required for user delegation SAS key generation)
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'

resource storageBlobOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountId, webApp.id, storageBlobDataOwnerRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Reference existing storage account for scoped role assignment
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: last(split(storageAccountId, '/'))
}

// Service Bus Data Sender: 69a216fc-b8fb-44d8-bc22-1f3c2cd27a39
var serviceBusDataSenderRoleId = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'

resource serviceBusRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusId, webApp.id, serviceBusDataSenderRoleId)
  scope: serviceBusNs
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataSenderRoleId)
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource serviceBusNs 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: last(split(serviceBusId, '/'))
}

@description('Web App resource ID')
output id string = webApp.id

@description('Web App name')
output name string = webApp.name

@description('Web App default hostname')
output defaultHostname string = webApp.properties.defaultHostName

@description('Web App managed identity principal ID')
output principalId string = webApp.identity.principalId
