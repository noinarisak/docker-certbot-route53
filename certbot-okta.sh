#!/usr/local/bin/bash

set -o pipefail

# Description: LetsEncypt + AWS Rout53 + Okta intergration. Poor mans Okta Custom Domain implementation.
# Requirements:
# - Docker
# - Route53 and AWS account (we need aws_access_key_id/aws_secret_access_key pair)
# - Okta Tenant
#
# Sample .env file:
# export AWS_ACCESS_KEY_ID=AKI..x
# export AWS_SECRET_ACCESS_KEY=Lq2...k
# export OKTA_ORG_NAME=narisak
# export OKTA_BASE_URL=okta.com
# export OKTA_API_TOKEN=00S...YW
# export OKTA_DOMAIN_ID=OcD...h8
# export CERTBOT_DOMAINS=atko.com,login.atko.com
# export CERTBOT_EMAIL=noi.narisak@atko.com
#

current_dir=$(pwd)
operation="certonly"
output_certbot_folder="certs"
certbot_domain_name="narisaklabs.com"
certbot_full_path="${output_certbot_folder}/live/${certbot_domain_name}"


if [ -z "${AWS_ACCESS_KEY_ID}" ]; then
    echo "Environment not set"
    exit 1
fi

if [ -z "${AWS_SECRET_ACCESS_KEY}" ]; then
    echo "Environment not set"
    exit 1
fi

if [ -z "${OKTA_ORG_NAME}" ]; then
    echo "Environment not set"
    exit 1
fi

if [ -z "${OKTA_BASE_URL}" ]; then
    echo "Environment not set"
    exit 1
fi

if [ -z "${OKTA_API_TOKEN}" ]; then
    echo "Environment not set"
    exit 1
fi

if [ -z "${OKTA_DOMAIN_ID}" ]; then
    echo "Environment not set"
    exit 1
fi

if [ -z "${CERTBOT_DOMAINS}" ]; then
    echo "Environment not set"
    exit 1
fi

if [ -z "${CERTBOT_EMAIL}" ]; then
    echo "Environment not set"
    exit 1
fi

if [ ! -f "${output_certbot_folder}" ]; then
    echo "Creating folder"
    mkdir ${output_certbot_folder}
fi

if ! docker info > /dev/null 2>&1 ; then
    echo "Script requires docker running, which it is not!"
    exit 1
fi

echo "Getting certbot/dns-route53 docker image:"
docker pull certbot/dns-route53:latest

echo "Running Certbot:"
docker run -it --rm --name certbot \
    --env AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
    --env AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
    -v "${current_dir}/certs:/etc/letsencrypt" \
    -v "/private/var/lib/letsencrypt:/var/lib/letsencrypt" \
    certbot/dns-route53 \
    --server https://acme-v02.api.letsencrypt.org/directory \
    --dns-route53 \
    --agree-tos \
    --config-dir "/etc/letsencrypt" \
    --work-dir "/etc/letsencrypt" \
    --logs-dir "/etc/letsencrypt" \
    --email "${CERTBOT_EMAIL}" \
    --domains "${CERTBOT_DOMAINS}" \
    $operation

DATARAW=$(echo '{}' | jq --arg privkey "$(<${certbot_full_path}/privkey.pem)" --arg cert "$(<${certbot_full_path}/cert.pem)" --arg certchain "$(<${certbot_full_path}/chain.pem)" '{"type": "PEM", "privateKey": $privkey, "certificate": $cert, "certificateChain": $certchain }')

echo "Raw JSON Payload:"
echo $DATARAW

echo "Update Okta Custom Domain:"
curl --location --request PUT "https://${OKTA_ORG_NAME}.${OKTA_BASE_URL}/api/v1/domains/${OKTA_DOMAIN_ID}/certificate" \
    --header 'Accept: application/json' \
    --header 'Content-Type: application/json' \
    --header "Authorization: SSWS ${OKTA_API_TOKEN}" \
    --data-raw "$DATARAW"

echo "New Expired Date:"
curl --location --request POST "https://${OKTA_ORG_NAME}.${OKTA_BASE_URL}/api/v1/domains/${OKTA_DOMAIN_ID}/verify" \
    --header 'Accept: application/json' \
    --header 'Content-Type: application/json' \
    --header "Authorization: SSWS ${OKTA_API_TOKEN}" \
    | jq '.["publicCertificate"].expiration'
