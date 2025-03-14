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

DOMAIN=$(python3 -c 'import os; print(os.getenv("DOMAIN", "zvx.my.id"))')
SUBDOMAIN="${domen}.${DOMAIN}"

CF_ID=$(python3 -c 'import os; print(os.getenv("CF_ID", "mezzqueen293@gmail.com"))')
CF_KEY=$(python3 -c 'import os; print(os.getenv("CF_KEY", "e03f30d53ad7ec2ab54327baa5e2da5ab44f0"))')

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

echo "${SUBDOMAIN}" | tee /root/domain /root/scdomain /etc/xray/domain /etc/v2ray/domain /etc/xray/scdomain
echo "DOMAIN=${SUBDOMAIN}" > /var/lib/kyt/ipvps.conf

echo "DNS for ${SUBDOMAIN} successfully updated!"

if ! command -v acme.sh &> /dev/null; then
    echo "Installing acme.sh..."
    curl https://get.acme.sh | sh
    source ~/.bashrc
fi

echo "Trying to get SSL certificate from Let's Encrypt..."
acme.sh --issue --standalone -d "${SUBDOMAIN}" --force --log > /tmp/acme.log 2>&1

if grep -q "429" /tmp/acme.log; then
    echo "Let's Encrypt rate limit reached. Switching to Cloudflare Origin Certificate..."

    CF_CERT_DATA=$(curl -sLX POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/ssl/origin_certificates" \
        -H "X-Auth-Email: ${CF_ID}" \
        -H "X-Auth-Key: ${CF_KEY}" \
        -H "Content-Type: application/json" \
        --data '{"hostnames":["'${SUBDOMAIN}'","*.'${SUBDOMAIN}'"],"request_type":"origin-rsa","validity_days":5475}')

    CF_CERT=$(echo "$CF_CERT_DATA" | jq -r ".result.certificate")
    CF_KEY=$(echo "$CF_CERT_DATA" | jq -r ".result.private_key")

    if [[ -z "$CF_CERT" || -z "$CF_KEY" ]]; then
        echo "Failed to generate Cloudflare Origin Certificate."
        exit 1
    fi

    mkdir -p /etc/ssl/cloudflare
    echo "$CF_CERT" > /etc/ssl/cloudflare/cert.pem
    echo "$CF_KEY" > /etc/ssl/cloudflare/key.pem

    echo "Cloudflare Origin Certificate generated successfully!"
    CERT_PATH="/etc/ssl/cloudflare/cert.pem"
    KEY_PATH="/etc/ssl/cloudflare/key.pem"
else
    echo "Let's Encrypt certificate obtained successfully!"
    CERT_PATH="/root/.acme.sh/${SUBDOMAIN}/fullchain.cer"
    KEY_PATH="/root/.acme.sh/${SUBDOMAIN}/${SUBDOMAIN}.key"
fi

echo "Configuring Nginx for SSL..."
cat <<EOF > /etc/nginx/sites-available/${SUBDOMAIN}
server {
    listen 443 ssl;
    server_name ${SUBDOMAIN};

    ssl_certificate ${CERT_PATH};
    ssl_certificate_key ${KEY_PATH};

    location / {
        proxy_pass http://localhost:8080;  # Sesuaikan dengan aplikasi Anda
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

ln -s /etc/nginx/sites-available/${SUBDOMAIN} /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

echo "SSL setup completed for ${SUBDOMAIN}!"
