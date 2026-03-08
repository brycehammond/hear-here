#!/usr/bin/env bash
# Configures Google and Apple as federated identity providers in Entra External ID.
# Entra identity provider federation cannot be managed via Bicep/ARM — it requires
# the Microsoft Graph API, which this script calls via the Azure CLI.
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - Permissions: IdentityProvider.ReadWrite.All on Microsoft Graph
#
# Usage:
#   ./setup-identity-providers.sh \
#     --google-client-id <GOOGLE_CLIENT_ID> \
#     --google-client-secret <GOOGLE_CLIENT_SECRET> \
#     --apple-client-id <APPLE_SERVICE_ID> \
#     --apple-key-id <APPLE_KEY_ID> \
#     --apple-team-id <APPLE_TEAM_ID> \
#     --apple-certificate-path <PATH_TO_P8_KEY>
#
# Google setup: https://console.developers.google.com/apis/credentials
#   1. Create an OAuth 2.0 Client ID (Web application type)
#   2. Add https://{tenant-name}.ciamlogin.com/te/{tenant-name}.onmicrosoft.com/oauth2/authresp
#      as an Authorized redirect URI
#
# Apple setup: https://developer.apple.com/account/resources
#   1. Register a Services ID with "Sign In with Apple" enabled
#   2. Configure the web domain and return URL:
#      https://{tenant-name}.ciamlogin.com/te/{tenant-name}.onmicrosoft.com/oauth2/authresp
#   3. Create a private key (.p8) for Sign In with Apple

set -euo pipefail

GOOGLE_CLIENT_ID=""
GOOGLE_CLIENT_SECRET=""
APPLE_CLIENT_ID=""
APPLE_KEY_ID=""
APPLE_TEAM_ID=""
APPLE_CERTIFICATE_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --google-client-id) GOOGLE_CLIENT_ID="$2"; shift 2 ;;
        --google-client-secret) GOOGLE_CLIENT_SECRET="$2"; shift 2 ;;
        --apple-client-id) APPLE_CLIENT_ID="$2"; shift 2 ;;
        --apple-key-id) APPLE_KEY_ID="$2"; shift 2 ;;
        --apple-team-id) APPLE_TEAM_ID="$2"; shift 2 ;;
        --apple-certificate-path) APPLE_CERTIFICATE_PATH="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

GRAPH_URL="https://graph.microsoft.com/v1.0"

get_access_token() {
    az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv
}

# --- Google Identity Provider ---
if [[ -n "$GOOGLE_CLIENT_ID" && -n "$GOOGLE_CLIENT_SECRET" ]]; then
    echo "Configuring Google identity provider..."

    TOKEN=$(get_access_token)

    EXISTING=$(curl -s -H "Authorization: Bearer $TOKEN" \
        "$GRAPH_URL/identity/identityProviders" \
        | python3 -c "import sys,json; providers=json.load(sys.stdin).get('value',[]); print(next((p['id'] for p in providers if p.get('displayName')=='Google'), ''))" 2>/dev/null || echo "")

    GOOGLE_BODY=$(cat <<EOJSON
{
    "@odata.type": "#microsoft.graph.socialIdentityProvider",
    "displayName": "Google",
    "identityProviderType": "Google",
    "clientId": "$GOOGLE_CLIENT_ID",
    "clientSecret": "$GOOGLE_CLIENT_SECRET"
}
EOJSON
)

    if [[ -n "$EXISTING" ]]; then
        echo "  Updating existing Google provider ($EXISTING)..."
        curl -s -X PATCH -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d "$GOOGLE_BODY" \
            "$GRAPH_URL/identity/identityProviders/$EXISTING"
    else
        echo "  Creating new Google provider..."
        curl -s -X POST -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d "$GOOGLE_BODY" \
            "$GRAPH_URL/identity/identityProviders"
    fi

    echo "  Google identity provider configured."
fi

# --- Apple Identity Provider ---
if [[ -n "$APPLE_CLIENT_ID" && -n "$APPLE_KEY_ID" && -n "$APPLE_TEAM_ID" && -n "$APPLE_CERTIFICATE_PATH" ]]; then
    echo "Configuring Apple identity provider..."

    if [[ ! -f "$APPLE_CERTIFICATE_PATH" ]]; then
        echo "  ERROR: Apple private key file not found at $APPLE_CERTIFICATE_PATH"
        exit 1
    fi

    # Generate the client secret JWT for Apple Sign In
    # Apple requires a JWT signed with the private key as the client secret
    APPLE_PRIVATE_KEY=$(cat "$APPLE_CERTIFICATE_PATH")

    TOKEN=$(get_access_token)

    EXISTING=$(curl -s -H "Authorization: Bearer $TOKEN" \
        "$GRAPH_URL/identity/identityProviders" \
        | python3 -c "import sys,json; providers=json.load(sys.stdin).get('value',[]); print(next((p['id'] for p in providers if p.get('displayName')=='Apple'), ''))" 2>/dev/null || echo "")

    APPLE_BODY=$(python3 -c "
import json
body = {
    '@odata.type': '#microsoft.graph.appleManagedIdentityProvider',
    'displayName': 'Apple',
    'developerId': '$APPLE_TEAM_ID',
    'serviceId': '$APPLE_CLIENT_ID',
    'keyId': '$APPLE_KEY_ID',
    'certificateData': '''$APPLE_PRIVATE_KEY'''
}
print(json.dumps(body))
")

    if [[ -n "$EXISTING" ]]; then
        echo "  Updating existing Apple provider ($EXISTING)..."
        curl -s -X PATCH -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d "$APPLE_BODY" \
            "$GRAPH_URL/identity/identityProviders/$EXISTING"
    else
        echo "  Creating new Apple provider..."
        curl -s -X POST -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d "$APPLE_BODY" \
            "$GRAPH_URL/identity/identityProviders"
    fi

    echo "  Apple identity provider configured."
fi

echo ""
echo "Done. Next steps:"
echo "  1. Go to the Entra admin center > External Identities > User flows"
echo "  2. Edit your 'B2C_1_signup_signin' user flow"
echo "  3. Under 'Identity providers', enable Google and/or Apple"
echo "  4. Save the user flow"
