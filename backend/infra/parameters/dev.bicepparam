using '../main.bicep'

param environment = 'dev'
param location = 'eastus2'
param projectName = 'hearhere'
param postgresAdminLogin = readEnvironmentVariable('POSTGRES_ADMIN_LOGIN', 'hearhereadmin')
param postgresAdminPassword = readEnvironmentVariable('POSTGRES_ADMIN_PASSWORD', '')
