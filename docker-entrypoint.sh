#!/bin/bash
set -e

# Start Redis server
echo "Starting Redis server..."
redis-server --daemonize yes

# Check if SESSION_SECRET is provided, if not generate a random one
if grep -q "replace_with_a_secure_random_string" /opt/chatgpt-github-integration/server/.env; then
  echo "Generating a secure random session secret..."
  RANDOM_SECRET=$(openssl rand -base64 32)
  sed -i "s/replace_with_a_secure_random_string/$RANDOM_SECRET/" /opt/chatgpt-github-integration/server/.env
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

# Start Nginx
echo "Starting Nginx..."
nginx

# Check if SSL is requested
if [ "$ENABLE_SSL" = "true" ] && [ ! -z "$SERVER_DOMAIN" ]; then
  if [ ! -z "$EMAIL_ADDRESS" ]; then
    echo "Setting up SSL with Let's Encrypt for $SERVER_DOMAIN"
    certbot --nginx -d $SERVER_DOMAIN --non-interactive --agree-tos -m $EMAIL_ADDRESS
  else
    echo "EMAIL_ADDRESS is required for SSL setup. SSL not configured."
  fi
fi

# Start the Node.js server
echo "Starting ChatGPT GitHub Integration server..."
cd /opt/chatgpt-github-integration/server
exec node server.js
