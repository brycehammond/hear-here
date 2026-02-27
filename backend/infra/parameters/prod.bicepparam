using '../main.bicep'

param environment = 'prod'
param location = 'eastus2'
param projectName = 'hearhere'
param postgresAdminLogin = readEnvironmentVariable('POSTGRES_ADMIN_LOGIN', '')
param postgresAdminPassword = readEnvironmentVariable('POSTGRES_ADMIN_PASSWORD', '')
