#!/bin/bash
set -euo pipefail

apt-get update
apt-get install -y jq curl

clear
echo -e ""
echo -e "\033[96;1m============================\033[0m"
echo -e "\033[93;1m      INPUT SUBDOMAIN"
echo -e "\033[96;1m============================\033[0m"
echo -e "\033[91;1m Note:"
echo -e "\033[91;1m Example:\033[0m \033[93mexample22\033[0m"
echo -e " "
read -r -p "SUBDOMAIN :  " domen
echo -e ""

DOMAIN="zvx.my.id"
SUBDOMAIN="${domen}.${DOMAIN}"

CF_ID="mezzqueen293@gmail.com"
CF_KEY="e03f30d53ad7ec2ab54327baa5e2da5ab44f0"


IP=$(wget -qO- icanhazip.com)


ZONE=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}&status=active" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" | jq -r ".result[0].id")

if [[ -z "$ZONE" || "$ZONE" == "null" ]]; then
    echo "Failed to get Zone ID. Please double check your Cloudflare DOMAIN or API KEY."
    exit 1
fi


RECORD=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records?name=${SUBDOMAIN}" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" | jq -r ".result[0].id")

if [[ -z "$RECORD" || "$RECORD" == "null" ]]; then
    echo "Adding a new DNS record for ${SUBDOMAIN}..."
    RECORD=$(curl -sLX POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" \
     --data '{"type":"A","name":"'${SUBDOMAIN}'","content":"'${IP}'","ttl":120,"proxied":false}' | jq -r '.result.id')
else
    echo "Updating DNS records for ${SUBDOMAIN}..."
    curl -sLX PUT "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records/${RECORD}" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" \
     --data '{"type":"A","name":"'${SUBDOMAIN}'","content":"'${IP}'","ttl":120,"proxied":false}'
fi


echo "$SUBDOMAIN" | tee /root/domain /root/scdomain /etc/xray/domain /etc/v2ray/domain /etc/xray/scdomain
echo "DOMAIN=$SUBDOMAIN" > /var/lib/kyt/ipvps.conf

echo "DNS for ${SUBDOMAIN} successfully updated!"
