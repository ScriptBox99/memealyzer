param basename string = ''
param location string = 'westus2'
param failover_location string = 'eastus2'
param cli_user_id string = ''

var secrets = [
  'get'
  'set'
  'list'
  'delete'
]

resource storage 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: '${basename}storage'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {}
}

resource form_recognizer 'Microsoft.CognitiveServices/accounts@2017-04-18' = {
  name: '${basename}fr'
  location: location
  kind: 'FormRecognizer'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: '${basename}fr'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource text_analytics 'Microsoft.CognitiveServices/accounts@2017-04-18' = {
  name: '${basename}ta'
  location: location
  kind: 'TextAnalytics'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: '${basename}ta'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource key_vault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: '${basename}kv'
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: [
      {
        objectId: cli_user_id
        permissions: {
          secrets: secrets
        }
        tenantId: subscription().tenantId
      }
      {
        objectId: aks.properties.identityProfile.kubeletidentity.objectId
        permissions: {
          secrets: secrets
        }
        tenantId: subscription().tenantId
      }
      {
        objectId: aks.identity.principalId
        permissions: {
          secrets: secrets
        }
        tenantId: subscription().tenantId
      }
      {
        objectId: function.identity.principalId
        permissions: {
          secrets: secrets
        }
        tenantId: subscription().tenantId
      }
    ]
  }
}

resource cosmos_key_secret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  name: '${key_vault.name}/CosmosKey'
  properties: {
    value: listKeys(cosmos_account.id, cosmos_account.apiVersion).primaryMasterKey
  }
}

resource storage_key_secret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  name: '${key_vault.name}/StorageKey'
  properties: {
    value: listKeys(storage.id, storage.apiVersion).keys[0].value
  }
}

resource signalr_connection_string_secret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  name: '${key_vault.name}/SignalRConnectionString'
  properties: {
    value: listKeys(signalr.id, signalr.apiVersion).primaryConnectionString
  }
}

resource storage_connection_string_secret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  name: '${key_vault.name}/StorageConnectionString'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storage.id, storage.apiVersion).keys[0].value}'
  }
}

resource service_bus_connection_string_secret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  name: '${key_vault.name}/ServiceBusConnectionString'
  properties: {
    value: listKeys(resourceId('Microsoft.ServiceBus/namespaces/authorizationRules', service_bus.name, 'RootManageSharedAccessKey'), service_bus.apiVersion).primaryConnectionString
  }
}

resource cosmos_account 'Microsoft.DocumentDB/databaseAccounts@2020-04-01' = {
  name: '${basename}cosmosaccount'
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        failoverPriority: 1
        locationName: failover_location
      }
      {
        failoverPriority: 0
        locationName: location
      }
    ]
  }
}

resource cosmos_sqldb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2020-04-01' = {
  name: '${cosmos_account.name}/memealyzer'
  properties: {
    options: {
      throughput: 400
    }
    resource: {
      id: 'memealyzer'
    }
  }
}

resource cosmos_sqldb_container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2020-04-01' = {
  name: '${cosmos_account.name}/memealyzer/images'
  properties: {
    options: {
      throughput: 400
    }
    resource: {
      partitionKey: {
        paths: [
          '/uid'
        ]
      }
      id: 'images'
      uniqueKeyPolicy: {
        uniqueKeys: [
          {
            paths: [
              '/uid'
            ]
          }
        ]
      }
    }
  }
}

resource aks 'Microsoft.ContainerService/managedClusters@2020-09-01' = {
  name: '${basename}aks'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: '1.19.3'
    nodeResourceGroup: '${basename}aksnodes'
    dnsPrefix: '${basename}aks'

    agentPoolProfiles: [
      {
        name: 'default'
        count: 1
        vmSize: 'Standard_A2_v2'
        mode: 'System'
      }
    ]
  }
}

resource logging 'Microsoft.Insights/components@2015-05-01' = {
  name: '${basename}ai'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource appconfig 'Microsoft.AppConfiguration/configurationStores@2020-06-01' = {
  name: '${basename}appconfig'
  location: location
  sku: {
    name: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

resource appconfig_borderstyle 'Microsoft.AppConfiguration/configurationStores/keyValues@2020-07-01-preview' = {
  name: '${appconfig.name}/borderStyle'
  properties: {
    value: 'solid'
  }
}

resource signalr 'Microsoft.SignalRService/signalR@2020-07-01-preview' = {
  name: '${basename}signalr'
  location: location
  sku: {
    name: 'Standard_S1'
    capacity: 1
  }
  properties: {
    cors: {
      allowedOrigins: [
        '*'
      ]
    }
    features: [
      {
        flag: 'ServiceMode'
        value: 'Serverless'
      }
    ]
  }
}

resource plan 'Microsoft.Web/serverfarms@2020-06-01' = {
  name: '${basename}plan'
  location: location
  sku: {
    tier: 'Standard'
    size: 'S1'
    name: 'S1'
  }
  properties: {}
}

resource function 'Microsoft.Web/sites@2020-06-01' = {
  name: '${basename}function'
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    siteConfig: {
      alwaysOn: true
      cors: {
        allowedOrigins: [
          '*'
        ]
        supportCredentials: false
      }
    }
  }
}

resource function_app_settings 'Microsoft.Web/sites/config@2018-11-01' = {
  name: '${basename}function/appsettings'
  properties: {
    'AZURE_KEYVAULT_ENDPOINT': key_vault.properties.vaultUri
    'AzureWebJobsStorage': 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storage.id, storage.apiVersion).keys[0].value}'
    'APPINSIGHTS_INSTRUMENTATIONKEY': logging.properties.InstrumentationKey
    'FUNCTIONS_WORKER_RUNTIME': 'dotnet'
    'FUNCTIONS_EXTENSION_VERSION': '~3'
    'WEBSITES_ENABLE_APP_SERVICE_STORAGE': 'false'
    'AZURE_CLIENT_SYNC_QUEUE_NAME': 'sync'
    'AZURE_STORAGE_CONNECTION_STRING_SECRET_NAME': 'StorageConnectionString'
    'AZURE_SIGNALR_CONNECTION_STRING_SECRET_NAME': 'SignalRConnectionString'
    'WEBSITE_RUN_FROM_PACKAGE': ''
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2019-12-01-preview' = {
  name: '${basename}acr'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: true
  }
}

resource service_bus 'Microsoft.ServiceBus/namespaces@2017-04-01' = {
  name: '${basename}sb'
  location: location
  sku: {
    name: 'Basic'
  }
}

resource messages 'Microsoft.ServiceBus/namespaces/queues@2017-04-01' = {
  name: '${service_bus.name}/messages'
  properties: {
    defaultMessageTimeToLive: 'PT30S'
  }
}

resource sync 'Microsoft.ServiceBus/namespaces/queues@2017-04-01' = {
  name: '${service_bus.name}/sync'
  properties: {
    defaultMessageTimeToLive: 'PT30S'
  }
}

module cli_perms './roles.bicep' = {
  name: 'cli_perms-${resourceGroup().name}'
  params: {
    principalId: cli_user_id
    principalType: 'User'
    rgName: resourceGroup().name
  }
}

module function_perms './roles.bicep' = {
  name: 'function_perms-${resourceGroup().name}'
  params: {
    principalId: function.identity.principalId
    rgName: resourceGroup().name
  }
}

module aks_kubelet_perms './roles.bicep' = {
  name: 'aks_kubelet_perms-${resourceGroup().name}'
  params: {
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    rgName: resourceGroup().name
  }
}

module aks_cluster_perms './rolesacr.bicep' = {
  name: 'aks_cluster_perms-${resourceGroup().name}'
  params: {
    principalId: aks.identity.principalId
    rgName: resourceGroup().name
  }
}