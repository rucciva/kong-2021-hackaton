#!/bin/bash

##
## Variables
##
HYDRA_ADMIN_URL="http://127.0.0.1:4445"
HYDRA_ADMIN_URL_FROM_KONG="http://hydra:4445"
HYDRA_OIDC_URL="http://127.0.0.1:4444"

KONG_ADMIN_URL="http://127.0.0.1:8001"
KONG_PROXY_ENDPOINT="127.0.0.1:8000"

CLIENT_LISTEN_PORT="5555"
CLIENT_OIDC_CALLBACK_URL="http://127.0.0.1:$CLIENT_LISTEN_PORT/callback"

AUDIENCE_TOKEN="bNyWD0wZG5cguxU4Mxpulw=="



set -euo pipefail

##
## Preparation
##
docker-compose up -d 
echo -n "waiting..."
until curl -sf "$HYDRA_ADMIN_URL/clients" > /dev/null ; do 
    sleep 1; echo -n "." 
done
until curl -sf "$KONG_ADMIN_URL" > /dev/null ; do 
    sleep 1; echo -n "." 
done

clear
echo "Let's Start"

##
## Step 1
##
echo
read -p "=== Create the Hydra (OIDC) client (press any key to continue)."
curl -sf "$HYDRA_ADMIN_URL/clients" \
    -d '
        {
            "audience": [ "kong:'"$AUDIENCE_TOKEN"'" ],
            "client_id": "client",
            "client_name": "client",
            "client_secret": "secret",
            "grant_types": [ "authorization_code", "refresh_token" ],
            "redirect_uris": [ "'"$CLIENT_OIDC_CALLBACK_URL"'" ],
            "response_types": [ "code", "id_token" ],
            "scope": "openid offline"
        }
    '\
    | jq .

##
## Step 2
##
echo
read -p "=== Create the Kong Consumer (press any key to continue)."
curl -sf "$KONG_ADMIN_URL/consumers/" -d "username=consumer&custom_id=some-id" | jq .

##
## Step 3
##
echo; echo
read -p "=== Configure the OAuth2 Audience (press any key to continue)."
curl -sf -X POST "$KONG_ADMIN_URL/consumers/consumer/oauth2-audiences" \
  --data  "audience=$AUDIENCE_TOKEN" \
  --data  "issuer=$HYDRA_OIDC_URL/" \
  --data  "client_id=client" \
  | jq .

##
## Step 4
##
echo; echo
read -p "=== Expose Mockbin API  (press any key to continue)."
echo "- Service:"
curl -sf -X PUT "$KONG_ADMIN_URL/services/2bf9ddc1-ffe4-4d49-ba2f-3814b9ce3af7" \
    --data  "url=https://mockbin.org/requests" \
  | jq .

echo; echo; echo "- Route:"
curl -sf -X PUT "$KONG_ADMIN_URL/services/2bf9ddc1-ffe4-4d49-ba2f-3814b9ce3af7/routes/8a5adc76-8e04-410a-9639-c987d8fa6fc0" \
    --data  "paths[]=/mockbin" \
    --data  "protocols[]=http"  \
  | jq .

##
## Step 5
##
echo; echo; 
read -p "=== Enable OAuth2-Audience Plugin on the Route (press any key to continue)."
curl -sf -X POST "$KONG_ADMIN_URL/routes/8a5adc76-8e04-410a-9639-c987d8fa6fc0/plugins" \
    --data "name=oauth2-audience"  \
    --data "config.issuer=$HYDRA_OIDC_URL/" \
    --data "config.oidc_conf_discovery=false" \
    --data "config.audience_prefix=kong:" \
    --data "config.introspection_endpoint=$HYDRA_ADMIN_URL_FROM_KONG/oauth2/introspect" \
    --data "config.ssl_verify=false" \
  | jq .
    
##    
## Step 6    
##
echo; echo
read -p "=== Start the Authorization Code flow (press any key to continue)."
docker-compose exec hydra \
    hydra token user \
        --client-id client \
        --client-secret secret \
        --audience "kong:$AUDIENCE_TOKEN" \
        --endpoint $HYDRA_OIDC_URL/ \
        --port $CLIENT_LISTEN_PORT \
        --scope openid,offline || true 

##
## Step 7
##
echo; echo "=== Invoke the API with Token"
read -p "Enter Access Token: " TOKEN
curl -s "http://$KONG_PROXY_ENDPOINT/mockbin" -H "Authorization: Bearer $TOKEN" | jq .

##
## Step 8
##
echo; 
read -p "=== Invoke the API with Invalid Token (press any key to continue)."
curl -s "http://$KONG_PROXY_ENDPOINT/mockbin" -H "Authorization: Bearer ${TOKEN}1" | jq .
