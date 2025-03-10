#!/bin/bash
set -e

# Get Redis password from environment or secret
if [ -f /run/secrets/redis_password ]; then
  REDIS_PASSWORD=$(cat /run/secrets/redis_password)
elif [ -z "$REDIS_PASSWORD" ]; then
  REDIS_PASSWORD="RedisSecurePassword!"
  echo "WARNING: Using default Redis password. Consider setting a custom password."
fi

# Start Redis server with security
echo "Starting Redis server with security..."
cat > /tmp/redis.conf << EOF
protected-mode yes
port 6379
bind 127.0.0.1
requirepass "$REDIS_PASSWORD"
maxclients 100
timeout 60
EOF

redis-server /tmp/redis.conf --daemonize yes

# Check if SESSION_SECRET is provided from Docker secrets, env var, or generate one
if [ -f /run/secrets/session_secret ]; then
  SESSION_SECRET=$(cat /run/secrets/session_secret)
  echo "Using session secret from Docker secret"
elif [ ! -z "$SESSION_SECRET" ]; then
  echo "Using session secret from environment variable"
else
  echo "Generating a secure random session secret..."
  SESSION_SECRET=$(openssl rand -base64 32)
fi

# Update session secret in .env file
sed -i "s/replace_with_a_secure_random_string/$SESSION_SECRET/" /opt/chatgpt-github-integration/server/.env

# Update Redis password in .env file
sed -i "s|redis://localhost:6379|redis://:${REDIS_PASSWORD}@localhost:6379|g" /opt/chatgpt-github-integration/server/.env

# Get GitHub credentials from secrets if available
if [ -f /run/secrets/github_client_id ]; then
  GITHUB_CLIENT_ID=$(cat /run/secrets/github_client_id)
fi

if [ -f /run/secrets/github_client_secret ]; then
  GITHUB_CLIENT_SECRET=$(cat /run/secrets/github_client_secret)
fi

# Update server domain if provided
if [ ! -z "$SERVER_DOMAIN" ]; then
  echo "Setting server domain to: $SERVER_DOMAIN"
  sed -i "s/your-server-domain.com/$SERVER_DOMAIN/g" /etc/nginx/sites-available/chatgpt-github-integration
  sed -i "s#https://your-server-domain.com/auth/github/callback#https://$SERVER_DOMAIN/auth/github/callback#g" /opt/chatgpt-github-integration/server/.env
fi

# Update GitHub OAuth credentials if provided
if [ ! -z "$GITHUB_CLIENT_ID" ]; then
  echo "Setting GitHub Client ID"
  sed -i "s/your_github_client_id/$GITHUB_CLIENT_ID/" /opt/chatgpt-github-integration/server/.env
fi

if [ ! -z "$GITHUB_CLIENT_SECRET" ]; then
  echo "Setting GitHub Client Secret"
  sed -i "s/your_github_client_secret/$GITHUB_CLIENT_SECRET/" /opt/chatgpt-github-integration/server/.env
fi

# Set Client Origin if provided
if [ ! -z "$CLIENT_ORIGIN" ]; then
  echo "Setting Client Origin to: $CLIENT_ORIGIN"
  sed -i "s#https://chat.openai.com#$CLIENT_ORIGIN#g" /opt/chatgpt-github-integration/server/.env
fi

# Create necessary directories with proper permissions
mkdir -p /opt/chatgpt-github-integration/logs
chown -R chatgptgit:chatgptgit /opt/chatgpt-github-integration/logs
chmod 750 /opt/chatgpt-github-integration/logs

# Start Nginx
echo "Starting Nginx..."
nginx

# Check if SSL is requested
if [ "$ENABLE_SSL" = "true" ] && [ ! -z "$SERVER_DOMAIN" ]; then
  if [ ! -z "$EMAIL_ADDRESS" ]; then
    echo "Setting up SSL with Let's Encrypt for $SERVER_DOMAIN"
    certbot --nginx -d $SERVER_DOMAIN --non-interactive --agree-tos -m $EMAIL_ADDRESS
    
    # Secure SSL configuration
    sed -i 's/ssl_protocols.*/ssl_protocols TLSv1.2 TLSv1.3;/' /etc/nginx/sites-available/chatgpt-github-integration
    sed -i 's/ssl_ciphers.*/ssl_ciphers "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256";/' /etc/nginx/sites-available/chatgpt-github-integration
    
    # Reload Nginx with the new SSL configuration
    nginx -s reload
  else
    echo "EMAIL_ADDRESS is required for SSL setup. SSL not configured."
  fi
fi

# Drop privileges before starting the Node.js server
echo "Starting ChatGPT GitHub Integration server..."
cd /opt/chatgpt-github-integration/server
exec su -s /bin/bash chatgptgit -c "NODE_ENV=production node server.js"
