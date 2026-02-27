@description('Environment name (dev, staging, prod)')
param environment string

@description('Azure region for resources')
param location string

@description('Project name used in resource naming')
param projectName string

@description('Tags to apply to all resources')
param tags object

var namespaceName = '${projectName}-sb-${environment}'
var skuName = environment == 'prod' ? 'Standard' : 'Basic'

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuName
  }
}

resource moderationQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'moderation-requests'
  properties: {
    maxDeliveryCount: 5
    lockDuration: 'PT1M'
    defaultMessageTimeToLive: 'P1D'
    deadLetteringOnMessageExpiration: true
    maxSizeInMegabytes: 1024
  }
}

@description('Service Bus namespace resource ID')
output id string = serviceBusNamespace.id

@description('Service Bus namespace name')
output namespaceName string = serviceBusNamespace.name

@description('Service Bus fully qualified namespace')
output fullyQualifiedNamespace string = '${serviceBusNamespace.name}.servicebus.windows.net'
