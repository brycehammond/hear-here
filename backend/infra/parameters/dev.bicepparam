using '../main.bicep'

param environment = 'dev'
param location = 'eastus2'
param projectName = 'hearhere'
param postgresAdminLogin = readEnvironmentVariable('POSTGRES_ADMIN_LOGIN', 'hearhereadmin')
param postgresAdminPassword = readEnvironmentVariable('POSTGRES_ADMIN_PASSWORD', '')
param postgresEntraAdminObjectId = readEnvironmentVariable('POSTGRES_ENTRA_ADMIN_OBJECT_ID', '')
param postgresEntraAdminName = readEnvironmentVariable('POSTGRES_ENTRA_ADMIN_NAME', 'hearhere-db-admins')
param postgresEntraAdminType = 'Group'
