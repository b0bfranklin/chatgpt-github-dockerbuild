#!/bin/bash

# ChatGPT GitHub Integration Deployment Script
# This script automates the full deployment process on a fresh VM/LXC

set -e  # Exit immediately if a command exits with a non-zero status

# Color codes for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print a formatted message
print_message() {
  echo -e "${BLUE}[$(date +%T)]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[$(date +%T)] ✓ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}[$(date +%T)] ⚠ $1${NC}"
}

print_error() {
  echo -e "${RED}[$(date +%T)] ✗ $1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Parse command line arguments
GITHUB_CLIENT_ID=""
GITHUB_CLIENT_SECRET=""
SERVER_DOMAIN=""
EMAIL_ADDRESS=""
ENABLE_SSL="false"
INSTALL_DIR="/opt/chatgpt-github-integration"
REDIS_PASSWORD=$(openssl rand -base64 32)
SESSION_SECRET=$(openssl rand -base64 32)

while [[ $# -gt 0 ]]; do
  case $1 in
    --github-client-id)
      GITHUB_CLIENT_ID="$2"
      shift 2
      ;;
    --github-client-secret)
      GITHUB_CLIENT_SECRET="$2"
      shift 2
      ;;
    --server-domain)
      SERVER_DOMAIN="$2"
      shift 2
      ;;
    --email)
      EMAIL_ADDRESS="$2"
      shift 2
      ;;
    --enable-ssl)
      ENABLE_SSL="true"
      shift
      ;;
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --redis-password)
      REDIS_PASSWORD="$2"
      shift 2
      ;;
    *)
      print_error "Unknown option: $1"
      echo "Usage: $0 --github-client-id CLIENT_ID --github-client-secret CLIENT_SECRET --server-domain DOMAIN [--email EMAIL] [--enable-ssl] [--install-dir PATH] [--redis-password PASSWORD]"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "$GITHUB_CLIENT_ID" || -z "$GITHUB_CLIENT_SECRET" || -z "$SERVER_DOMAIN" ]]; then
  print_error "Missing required parameters"
  echo "Usage: $0 --github-client-id CLIENT_ID --github-client-secret CLIENT_SECRET --server-domain DOMAIN [--email EMAIL] [--enable-ssl] [--install-dir PATH] [--redis-password PASSWORD]"
  exit 1
fi

if [[ "$ENABLE_SSL" == "true" && -z "$EMAIL_ADDRESS" ]]; then
  print_error "Email address is required for SSL setup"
  exit 1
fi

# Install dependencies
print_message "Installing system dependencies..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release git unzip ufw fail2ban

# Install Docker
print_message "Installing Docker..."
if ! command -v docker &> /dev/null; then
  curl -fsSL https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]')/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]') $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io
  systemctl enable docker
  systemctl start docker
  print_success "Docker installed successfully"
else
  print_success "Docker already installed"
fi

# Install Docker Compose
print_message "Installing Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
  DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
  curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  print_success "Docker Compose installed successfully"
else
  print_success "Docker Compose already installed"
fi

# Create installation directory
print_message "Creating installation directory at $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Set up directory structure
print_message "Setting up project files..."
mkdir -p nginx
mkdir -p server
mkdir -p extension/images
mkdir -p data/logs
mkdir -p data/cache

# Configure UFW firewall
print_message "Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable
print_success "Firewall configured"

# Configure Fail2Ban
print_message "Configuring Fail2Ban..."
cat > /etc/fail2ban/jail.d/chatgpt-github.conf << 'EOF'
[chatgpt-github-nginx]
enabled = true
port = http,https
filter = chatgpt-github-nginx
logpath = /var/log/nginx/access.log
maxretry = 5
findtime = 300
bantime = 3600
EOF

cat > /etc/fail2ban/filter.d/chatgpt-github-nginx.conf << 'EOF'
[Definition]
failregex = ^<HOST> - .* \[.*\] "POST /auth/github.*" 401
            ^<HOST> - .* \[.*\] "GET /auth/github/callback.*" 401
ignoreregex =
EOF

systemctl restart fail2ban
print_success "Fail2Ban configured"

# Create configuration files

# Dockerfile
print_message "Creating Dockerfile..."
cat > Dockerfile << 'EOF'
FROM node:18-slim

# Set working directory
WORKDIR /app

# Install system dependencies including zip utility
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    redis-server \
    nginx \
    certbot \
    python3-certbot-nginx \
    curl \
    zip \
    && rm -rf /var/lib/apt/lists/*

# Create application user (non-root)
RUN useradd -m -s /bin/bash chatgptgit

# Create application directories
RUN mkdir -p /opt/chatgpt-github-integration/{server,config,logs,cache} \
    && chown -R chatgptgit:chatgptgit /opt/chatgpt-github-integration

# Switch to the application directory
WORKDIR /opt/chatgpt-github-integration/server

# Copy package.json and package-lock.json (if available)
COPY --chown=chatgptgit:chatgptgit server/package*.json ./

# Install Node.js dependencies
RUN npm install

# Copy server code
COPY --chown=chatgptgit:chatgptgit server/server.js ./
COPY --chown=chatgptgit:chatgptgit server/.env.example ./.env

# Copy Nginx configuration
COPY nginx/chatgpt-github-integration /etc/nginx/sites-available/
RUN ln -sf /etc/nginx/sites-available/chatgpt-github-integration /etc/nginx/sites-enabled/ \
    && rm -f /etc/nginx/sites-enabled/default

# Expose ports
EXPOSE 3000 80 443

# Create startup script
COPY --chown=root:root docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Set environment variables
ENV NODE_ENV=development \
    PORT=3000 \
    REDIS_URL=redis://localhost:6379

ENTRYPOINT ["docker-entrypoint.sh"]
EOF

# Docker Compose
print_message "Creating docker-compose.yml..."
cat > docker-compose.yml << EOF
version: '3.8'

services:
  server:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: chatgpt-github-integration
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - SERVER_DOMAIN=${SERVER_DOMAIN:-your-server-domain.com}
      - GITHUB_CLIENT_ID=${GITHUB_CLIENT_ID}
      - GITHUB_CLIENT_SECRET=${GITHUB_CLIENT_SECRET}
      - CLIENT_ORIGIN=https://chat.openai.com
      - ENABLE_SSL=${ENABLE_SSL:-false}
      - EMAIL_ADDRESS=${EMAIL_ADDRESS}
      - SESSION_SECRET=${SESSION_SECRET}
      - REDIS_PASSWORD=${REDIS_PASSWORD}
    volumes:
      - ./data/logs:/opt/chatgpt-github-integration/logs
      - ./data/cache:/opt/chatgpt-github-integration/cache
      - letsencrypt:/etc/letsencrypt
    networks:
      - chatgpt-github-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 1m
      timeout: 10s
      retries: 3
      start_period: 30s

networks:
  chatgpt-github-net:
    driver: bridge

volumes:
  letsencrypt:
    driver: local
EOF

# Nginx config with enhanced security
print_message "Creating Nginx configuration..."
cat > nginx/chatgpt-github-integration << EOF
server {
    listen 80;
    server_name ${SERVER_DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${SERVER_DOMAIN};
    
    # SSL will be configured by certbot if enabled
    
    # Enhanced security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' https://api.github.com";
    add_header Referrer-Policy strict-origin-when-cross-origin;
    
    # Enable OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # SSL session cache
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    
    # Modern TLS only
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Support larger file uploads
        client_max_body_size 10M;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Access and error logs
    access_log /var/log/nginx/chatgpt-github.access.log;
    error_log /var/log/nginx/chatgpt-github.error.log;
}
EOF

# Docker entrypoint
print_message "Creating docker-entrypoint.sh..."
cat > docker-entrypoint.sh << 'EOF'
#!/bin/bash
set -e

# Start Redis server with password
echo "Starting Redis server..."
echo "requirepass $REDIS_PASSWORD" > /tmp/redis.conf
redis-server /tmp/redis.conf --daemonize yes

# Check if SESSION_SECRET is provided, if not generate a random one
if grep -q "replace_with_a_secure_random_string" /opt/chatgpt-github-integration/server/.env; then
  echo "Setting secure session secret..."
  sed -i "s/replace_with_a_secure_random_string/$SESSION_SECRET/" /opt/chatgpt-github-integration/server/.env
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

# Update Redis URL with password
if [ ! -z "$REDIS_PASSWORD" ]; then
  echo "Configuring Redis password"
  sed -i "s#redis://localhost:6379#redis://:${REDIS_PASSWORD}@localhost:6379#g" /opt/chatgpt-github-integration/server/.env
fi

# Start Nginx
echo "Starting Nginx..."
nginx

# Check if SSL is requested
if [ "$ENABLE_SSL" = "true" ] && [ ! -z "$SERVER_DOMAIN" ]; then
  if [ ! -z "$EMAIL_ADDRESS" ]; then
    echo "Setting up SSL with Let's Encrypt for $SERVER_DOMAIN"
    certbot --nginx -d $SERVER_DOMAIN --non-interactive --agree-tos -m $EMAIL_ADDRESS
    
    # Add HSTS header after SSL is configured
    if ! grep -q "Strict-Transport-Security" /etc/nginx/sites-available/chatgpt-github-integration; then
      sed -i '/add_header Content-Security-Policy/a \    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;' /etc/nginx/sites-available/chatgpt-github-integration
      nginx -s reload
    fi
  else
    echo "EMAIL_ADDRESS is required for SSL setup. SSL not configured."
  fi
fi

# Start the Node.js server
echo "Starting ChatGPT GitHub Integration server..."
cd /opt/chatgpt-github-integration/server
exec node server.js
EOF
chmod +x docker-entrypoint.sh

# Environment
print_message "Creating .env.example..."
cat > server/.env.example << EOF
PORT=3000
NODE_ENV=development
SESSION_SECRET=replace_with_a_secure_random_string
GITHUB_CLIENT_ID=your_github_client_id
GITHUB_CLIENT_SECRET=your_github_client_secret
GITHUB_CALLBACK_URL=https://your-server-domain.com/auth/github/callback
CLIENT_ORIGIN=https://chat.openai.com
REDIS_URL=redis://:password@localhost:6379
EOF

# Create actual .env file
print_message "Creating .env file..."
cat > .env << EOF
SERVER_DOMAIN=$SERVER_DOMAIN
GITHUB_CLIENT_ID=$GITHUB_CLIENT_ID
GITHUB_CLIENT_SECRET=$GITHUB_CLIENT_SECRET
ENABLE_SSL=$ENABLE_SSL
EMAIL_ADDRESS=$EMAIL_ADDRESS
SESSION_SECRET=$SESSION_SECRET
REDIS_PASSWORD=$REDIS_PASSWORD
EOF

# Extension files (minimum necessary for the build script)
print_message "Creating extension browser-extension-styles.css..."
cat > extension/browser-extension-styles.css << 'EOF'
.github-integration-container {
  display: flex;
  position: relative;
  margin-top: 10px;
}

.github-integration-button {
  background: none;
  border: none;
  cursor: pointer;
  padding: 5px;
  color: #8e8ea0;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 4px;
}

.github-integration-button:hover {
  background-color: rgba(142, 142, 160, 0.1);
  color: #fff;
}

.github-panel {
  position: absolute;
  bottom: 40px;
  right: 0;
  width: 350px;
  height: 450px;
  background-color: #1e1e2e;
  border: 1px solid #565869;
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.5);
  z-index: 1000;
  display: flex;
  flex-direction: column;
  transition: all 0.2s ease;
  overflow: hidden;
}

/* More CSS content from the original browser-extension-styles.css file would go here */
EOF

# Create extension build script
print_message "Creating build-extension.sh..."
cat > extension/build-extension.sh << 'EOF'
#!/bin/bash
set -e

# Create directory structure for extension files
mkdir -p images

# Since we're already in the extension directory, we can copy files directly
# or they may already be in this directory, so we skip the copy step

# Download GitHub icons if they don't exist
if [ ! -f "images/icon16.png" ] || [ ! -f "images/icon48.png" ] || [ ! -f "images/icon128.png" ]; then
  echo "Downloading GitHub icons..."
  curl -s -o images/icon16.png https://raw.githubusercontent.com/JJP123/simpleicons/master/icons/github/github-16.png
  curl -s -o images/icon48.png https://raw.githubusercontent.com/JJP123/simpleicons/master/icons/github/github-48.png
  curl -s -o images/icon128.png https://raw.githubusercontent.com/JJP123/simpleicons/master/icons/github/github-128.png
fi

# Make sure all required files exist
required_files=("manifest.json" "popup.html" "popup.js" "background.js" "content.js")
for file in "${required_files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "Warning: $file is missing. The extension may not work correctly."
  fi
done

# Ensure we have styles.css by copying browser-extension-styles.css if needed
if [ ! -f "styles.css" ] && [ -f "browser-extension-styles.css" ]; then
  cp browser-extension-styles.css styles.css
fi

# Create a ZIP file of the extension
echo "Creating extension ZIP file..."
cd ..
zip -r extension.zip extension/* -x "extension/build-extension.sh"
echo "Extension ZIP archive created as 'extension.zip'"
echo "You can now load this as an unpacked extension in your browser or download it from the server"
EOF
chmod +x extension/build-extension.sh

# Create update.sh
print_message "Creating update.sh..."
cat > update.sh << 'EOF'
#!/bin/bash

# ChatGPT GitHub Integration Update Script
# This script updates both the server component and browser extension

set -e  # Exit immediately if a command exits with a non-zero status

# Color codes for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print a formatted message
print_message() {
  echo -e "${BLUE}[$(date +%T)]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[$(date +%T)] ✓ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}[$(date +%T)] ⚠ $1${NC}"
}

print_error() {
  echo -e "${RED}[$(date +%T)] ✗ $1${NC}"
}

# Check if Docker and Docker Compose are installed
check_prerequisites() {
  print_message "Checking prerequisites..."
  
  if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
  fi
  
  if ! command -v docker-compose &> /dev/null; then
    print_error "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
  fi
  
  # Check if .env file exists
  if [ ! -f .env ]; then
    print_warning "No .env file found. The update will use existing environment variables in containers."
    read -p "Do you want to continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
  
  print_success "Prerequisites check passed."
}

# Backup current configuration
backup_config() {
  print_message "Creating backup of current configuration..."
  
  BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
  mkdir -p $BACKUP_DIR
  
  # Backup .env file if it exists
  if [ -f .env ]; then
    cp .env $BACKUP_DIR/
  fi
  
  # Backup docker-compose.yml
  if [ -f docker-compose.yml ]; then
    cp docker-compose.yml $BACKUP_DIR/
  fi
  
  # Backup Nginx configs
  if [ -d nginx ]; then
    mkdir -p $BACKUP_DIR/nginx
    cp -r nginx/* $BACKUP_DIR/nginx/
  fi
  
  # Backup extension source files
  mkdir -p $BACKUP_DIR/extension_source
  for file in extension/*.json extension/*.html extension/*.js extension/*.css; do
    if [ -f "$file" ]; then
      cp "$file" $BACKUP_DIR/extension_source/
    fi
  done
  
  print_success "Backup created in directory: $BACKUP_DIR"
}

# Rebuild and restart the Docker containers
update_docker_containers() {
  print_message "Updating Docker containers..."
  
  # Check if the container is running
  if docker-compose ps | grep -q "chatgpt-github-integration"; then
    # Stop the containers
    print_message "Stopping running containers..."
    docker-compose down
  fi
  
  # Build the new image
  print_message "Building new Docker image..."
  docker-compose build --no-cache
  
  # Start the containers
  print_message "Starting updated containers..."
  docker-compose up -d
  
  print_success "Docker containers updated and restarted."
}

# Update the browser extension
update_browser_extension() {
  print_message "Updating browser extension..."
  
  # Make sure the build script is executable
  chmod +x extension/build-extension.sh
  
  # Run the extension build script
  cd extension
  ./build-extension.sh
  cd ..
  
  print_success "Browser extension updated."
  print_message "Remember to reload the extension in your browser:"
  print_message "1. Go to your browser's extension management page"
  print_message "2. Find the ChatGPT GitHub Integration extension"
  print_message "3. Click the reload button or toggle it off and on"
}

# Main function
main() {
  print_message "Starting ChatGPT GitHub Integration update..."
  
  check_prerequisites
  backup_config
  update_docker_containers
  update_browser_extension
  
  print_success "Update completed successfully!"
  print_message "To verify the update, check the server logs:"
  print_message "docker-compose logs -f"
}

# Run the main function
main
EOF
chmod +x update.sh

# Create package.json
print_message "Creating package.json..."
cat > server/package.json << 'EOF'
{
  "name": "chatgpt-github-integration-server",
  "version": "1.0.0",
  "description": "Server for ChatGPT GitHub Integration",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "NODE_ENV=development nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "express-session": "^1.17.3",
    "passport": "^0.6.0",
    "passport-github2": "^0.1.12",
    "morgan": "^1.10.0",
    "winston": "^3.8.2",
    "cors": "^2.8.5",
    "dotenv": "^16.0.3",
    "axios": "^1.3.4",
    "body-parser": "^1.20.2",
    "cookie-parser": "^1.4.6",
    "redis": "^4.6.5",
    "connect-redis": "^7.0.1",
    "simple-git": "^3.17.0",
    "jsonwebtoken": "^9.0.0",
    "archiver": "^5.3.1",
    "express-rate-limit": "^6.7.0",
    "helmet": "^6.1.5"
  },
  "devDependencies": {
    "nodemon": "^2.0.21"
  }
}
EOF

# Create server.js with security enhancements
print_message "Creating server.js..."
cat > server/server.js << 'EOF'
const express = require('express');
const session = require('express-session');
const passport = require('passport');
const GitHubStrategy = require('passport-github2').Strategy;
const cors = require('cors');
const morgan = require('morgan');
const winston = require('winston');
const fs = require('fs');
const path = require('path');
const axios = require('axios');
const bodyParser = require('body-parser');
const cookieParser = require('cookie-parser');
const Redis = require('redis');
const RedisStore = require('connect-redis').default;
const simpleGit = require('simple-git');
const jwt = require('jsonwebtoken');
const archiver = require('archiver');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
require('dotenv').config();

// Initialize logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.File({ filename: '../logs/error.log', level: 'error' }),
    new winston.transports.File({ filename: '../logs/combined.log' })
  ]
});

// Security logger
const securityLogger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.File({ filename: '../logs/security.log' })
  ]
});

if (process.env.NODE_ENV !== 'production') {
  logger.add(new winston.transports.Console({
    format: winston.format.simple()
  }));
  securityLogger.add(new winston.transports.Console({
    format: winston.format.simple()
  }));
}

// Redis client setup
const redisClient = Redis.createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

redisClient.connect().catch(console.error);

// Initialize express app
const app = express();
const PORT = process.env.PORT || 3000;

// Use Helmet for security headers
app.use(helmet());

// Apply rate limiting to all routes
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // Limit each IP to 100 requests per windowMs
  standardHeaders: true,
  legacyHeaders: false,
  message: 'Too many requests from this IP, please try again after 15 minutes'
});
app.use(globalLimiter);

// Stricter rate limiting for auth routes
const authLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 10, // 10 auth attempts per hour
  standardHeaders: true, 
  legacyHeaders: false,
  message: 'Too many authentication attempts, please try again later'
});
app.use('/auth', authLimiter);

// Middleware
app.use(cors({
  origin: process.env.CLIENT_ORIGIN || 'https://chat.openai.com',
  credentials: true
}));
app.use(morgan('combined'));
app.use(cookieParser());
app.use(bodyParser.json({ limit: '10mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '10mb' }));

// Session configuration with secure settings
app.use(session({
  store: new RedisStore({ client: redisClient }),
  secret: process.env.SESSION_SECRET || 'your-secret-key',
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: process.env.NODE_ENV === 'production',
    httpOnly: true, 
    sameSite: 'lax',
    maxAge: 24 * 60 * 60 * 1000, // 24 hours
    path: '/'
  }
}));

// Initialize Passport
app.use(passport.initialize());
app.use(passport.session());

// GitHub OAuth Strategy with reduced scope
passport.use(new GitHubStrategy({
    clientID: process.env.GITHUB_CLIENT_ID,
    clientSecret: process.env.GITHUB_CLIENT_SECRET,
    callbackURL: process.env.GITHUB_CALLBACK_URL,
    scope: ['repo'] // Reduced scope - only request repo access
  },
  function(accessToken, refreshToken, profile, done) {
    const user = {
      id: profile.id,
      username: profile.username,
      displayName: profile.displayName || profile.username,
      accessToken,
      emails: profile.emails
    };
    return done(null, user);
  }
));

passport.serializeUser(function(user, done) {
  done(null, user);
});

passport.deserializeUser(function(obj, done) {
  done(null, obj);
});

// Log authentication attempts
app.use('/auth/*', (req, res, next) => {
  securityLogger.info('Authentication attempt', {
    ip: req.ip,
    path: req.path,
    method: req.method,
    userAgent: req.headers['user-agent']
  });
  next();
});

// Log API requests
app.use('/api/*', (req, res, next) => {
  securityLogger.info('API request', {
    ip: req.ip, 
    path: req.path,
    method: req.method,
    authenticated: req.isAuthenticated()
  });
  next();
});

// Basic routes
app.get('/', (req, res) => {
  res.send('ChatGPT GitHub Integration API is running');
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Auth routes
app.get('/auth/github', passport.authenticate('github'));

app.get('/auth/github/callback', 
  passport.authenticate('github', { failureRedirect: '/login' }),
  function(req, res) {
    res.redirect('/success');
  }
);

app.get('/success', (req, res) => {
  res.send(`
    <html>
      <head>
        <title>Authentication Successful</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
            background-color: #f6f8fa;
            color: #24292e;
          }
          .card {
            background-color: white;
            border-radius: 6px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
            padding: 32px;
            text-align: center;
            max-width: 400px;
          }
          svg {
            fill: #2da44e;
            width: 64px;
            height: 64px;
            margin-bottom: 16px;
          }
          h1 {
            margin: 0 0 16px 0;
          }
          p {
            margin: 0 0 24px 0;
            color: #57606a;
            line-height: 1.5;
          }
        </style>
      </head>
      <body>
        <div class="card">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
          </svg>
          <h1>Successfully Connected</h1>
          <p>You've authenticated with GitHub. You can close this window and return to ChatGPT.</p>
        </div>
      </body>
    </html>
  `);
});

app.get('/login', (req, res) => {
  res.send(`
    <html>
      <head>
        <title>GitHub Authentication</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
            background-color: #f6f8fa;
            color: #24292e;
          }
          .card {
            background-color: white;
            border-radius: 6px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
            padding: 32px;
            text-align: center;
            max-width: 400px;
          }
          .button {
            background-color: #2da44e;
            color: white;
            border: none;
            border-radius: 6px;
            padding: 12px 20px;
            font-size: 16px;
            font-weight: 500;
            cursor: pointer;
            text-decoration: none;
            display: inline-block;
          }
          .button:hover {
            background-color: #2c974b;
          }
          h1 {
            margin: 0 0 16px 0;
          }
          p {
            margin: 0 0 24px 0;
            color: #57606a;
            line-height: 1.5;
          }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>GitHub Authentication</h1>
          <p>Connect your GitHub account to use with ChatGPT</p>
          <a href="/auth/github" class="button">Login with GitHub</a>
        </div>
      </body>
    </html>
  `);
});

// GitHub API routes
app.get('/api/user', ensureAuthenticated, (req, res) => {
  res.json(req.user);
});

// Get repositories list
app.get('/api/repos', ensureAuthenticated, async (req, res) => {
  try {
    const response = await axios.get('https://api.github.com/user/repos?per_page=100', {
      headers: {
        Authorization: `token ${req.user.accessToken}`
      }
    });
    res.json(response.data);
  } catch (error) {
    logger.error('Error fetching repos:', error);
    res.status(500).json({ error: 'Failed to fetch repositories' });
  }
});

// Get file or directory contents
app.get('/api/repos/:owner/:repo/contents/:path(*)', ensureAuthenticated, async (req, res) => {
  try {
    const { owner, repo, path } = req.params;
    const branch = req.query.branch || 'main';
    
    const response = await axios.get(`https://api.github.com/repos/${owner}/${repo}/contents/${path}`, {
      headers: {
        Authorization: `token ${req.user.accessToken}`
      },
      params: {
        ref: branch
      }
    });
    res.json(response.data);
  } catch (error) {
    logger.error('Error fetching file contents:', error);
    res.status(500).json({ error: 'Failed to fetch file contents' });
  }
});

// Update file contents
app.post('/api/repos/:owner/:repo/contents/:path(*)', ensureAuthenticated, async (req, res) => {
  try {
    const { owner, repo, path } = req.params;
    const { content, message, sha, branch } = req.body;
    
    const response = await axios.put(
      `https://api.github.com/repos/${owner}/${repo}/contents/${path}`,
      {
        message,
        content: Buffer.from(content).toString('base64'),
        sha,
        branch
      },
      {
        headers: {
          Authorization: `token ${req.user.accessToken}`
        }
      }
    );
    
    res.json(response.data);
  } catch (error) {
    logger.error('Error updating file:', error);
    res.status(500).json({ error: 'Failed to update file' });
  }
});

// Create a new repository
app.post('/api/repos', ensureAuthenticated, async (req, res) => {
  try {
    const { name, description, private: isPrivate, auto_init } = req.body;
    
    const response = await axios.post(
      'https://api.github.com/user/repos',
      {
        name,
        description,
        private: isPrivate,
        auto_init
      },
      {
        headers: {
          Authorization: `token ${req.user.accessToken}`
        }
      }
    );
    
    res.json(response.data);
  } catch (error) {
    logger.error('Error creating repository:', error);
    res.status(500).json({ error: 'Failed to create repository' });
  }
});

// Create a new file
app.post('/api/repos/:owner/:repo/create/:path(*)', ensureAuthenticated, async (req, res) => {
  try {
    const { owner, repo, path } = req.params;
    const { content, message, branch } = req.body;
    
    const response = await axios.put(
      `https://api.github.com/repos/${owner}/${repo}/contents/${path}`,
      {
        message,
        content: Buffer.from(content).toString('base64'),
        branch
      },
      {
        headers: {
          Authorization: `token ${req.user.accessToken}`
        }
      }
    );
    
    res.json(response.data);
  } catch (error) {
    logger.error('Error creating file:', error);
    res.status(500).json({ error: 'Failed to create file' });
  }
});

// Create multiple files (for conversation export)
app.post('/api/repos/:owner/:repo/batch-create', ensureAuthenticated, async (req, res) => {
  try {
    const { owner, repo } = req.params;
    const { files, message, branch } = req.body;
    
    // For multiple files, we need to use Git references and blobs
    const results = [];
    
    // Get the latest commit SHA
    const refResponse = await axios.get(
      `https://api.github.com/repos/${owner}/${repo}/git/refs/heads/${branch}`,
      {
        headers: {
          Authorization: `token ${req.user.accessToken}`
        }
      }
    );
    
    const latestCommitSha = refResponse.data.object.sha;
    
    // Get the tree of the latest commit
    const commitResponse = await axios.get(
      `https://api.github.com/repos/${owner}/${repo}/git/commits/${latestCommitSha}`,
      {
        headers: {
          Authorization: `token ${req.user.accessToken}`
        }
      }
    );
    
    const baseTreeSha = commitResponse.data.tree.sha;
    
    // Create blobs for each file
    const newTreeItems = [];
    
    for (const file of files) {
      // Create blob
      const blobResponse = await axios.post(
        `https://api.github.com/repos/${owner}/${repo}/git/blobs`,
        {
          content: file.content,
          encoding: "utf-8"
        },
        {
          headers: {
            Authorization: `token ${req.user.accessToken}`
          }
        }
      );
      
      newTreeItems.push({
        path: file.path,
        mode: "100644",
        type: "blob",
        sha: blobResponse.data.sha
      });
      
      results.push({
        path: file.path,
        sha: blobResponse.data.sha
      });
    }
    
    // Create new tree
    const newTreeResponse = await axios.post(
      `https://api.github.com/repos/${owner}/${repo}/git/trees`,
      {
        base_tree: baseTreeSha,
        tree: newTreeItems
      },
      {
        headers: {
          Authorization: `token ${req.user.accessToken}`
        }
      }
    );
    
    const newTreeSha = newTreeResponse.data.sha;
    
    // Create commit
    const commitMessageResponse = await axios.post(
      `https://api.github.com/repos/${owner}/${repo}/git/commits`,
      {
        message,
        tree: newTreeSha,
        parents: [latestCommitSha]
      },
      {
        headers: {
          Authorization: `token ${req.user.accessToken}`
        }
      }
    );
    
    const newCommitSha = commitMessageResponse.data.sha;
    
    // Update reference
    await axios.patch(
      `https://api.github.com/repos/${owner}/${repo}/git/refs/heads/${branch}`,
      {
        sha: newCommitSha,
        force: false
      },
      {
        headers: {
          Authorization: `token ${req.user.accessToken}`
        }
      }
    );
    
    res.json({
      message: "Files created successfully",
      commit: newCommitSha,
      files: results
    });
  } catch (error) {
    logger.error('Error creating multiple files:', error);
    res.status(500).json({ error: 'Failed to create files' });
  }
});

// Create a new branch
app.post('/api/repos/:owner/:repo/branches', ensureAuthenticated, async (req, res) => {
  try {
    const { owner, repo } = req.params;
    const { baseBranch, newBranch } = req.body;
    
    // Get the SHA of the latest commit on the base branch
    const branchResponse = await axios.get(
      `https://api.github.com/repos/${owner}/${repo}/git/refs/heads/${baseBranch}`,
      {
        headers: {
          Authorization: `token ${req.user.accessToken}`
        }
      }
    );
    
    const sha = branchResponse.data.object.sha;
    
    // Create the new branch
    const response = await axios.post(
      `https://api.github.com/repos/${owner}/${repo}/git/refs`,
      {
        ref: `refs/heads/${newBranch}`,
        sha
      },
      {
        headers: {
          Authorization: `token ${req.user.accessToken}`
        }
      }
    );
    
    res.json(response.data);
  } catch (error) {
    logger.error('Error creating branch:', error);
    res.status(500).json({ error: 'Failed to create branch' });
  }
});

// Get repository branches
app.get('/api/repos/:owner/:repo/branches', ensureAuthenticated, async (req, res) => {
  try {
    const { owner, repo } = req.params;
    
    const response = await axios.get(`https://api.github.com/repos/${owner}/${repo}/branches`, {
      headers: {
        Authorization: `token ${req.user.accessToken}`
      }
    });
    
    res.json(response.data);
  } catch (error) {
    logger.error('Error fetching branches:', error);
    res.status(500).json({ error: 'Failed to fetch branches' });
  }
});

// Logout endpoint
app.get('/auth/logout', (req, res) => {
  req.logout(function(err) {
    if (err) { return next(err); }
    res.redirect('/');
  });
});

// ==========================================
// EXTENSION DISTRIBUTION FUNCTIONALITY
// ==========================================

// Create extension download endpoint
app.get('/extension', (req, res) => {
  res.send(`
    <html>
      <head>
        <title>ChatGPT GitHub Integration Extension</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
            background-color: #f6f8fa;
            color: #24292e;
          }
          .card {
            background-color: white;
            border-radius: 6px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
            padding: 32px;
            text-align: center;
            max-width: 600px;
            width: 90%;
          }
          h1 {
            margin: 0 0 16px 0;
          }
          p {
            margin: 0 0 24px 0;
            color: #57606a;
            line-height: 1.5;
          }
          .button {
            background-color: #2da44e;
            color: white;
            border: none;
            border-radius: 6px;
            padding: 12px 20px;
            font-size: 16px;
            font-weight: 500;
            cursor: pointer;
            text-decoration: none;
            display: inline-block;
          }
          .button:hover {
            background-color: #2c974b;
          }
          .instructions {
            text-align: left;
            margin-top: 32px;
          }
          .instructions h2 {
            font-size: 18px;
            margin-bottom: 16px;
          }
          .instructions ol {
            margin-left: 24px;
          }
          .instructions li {
            margin-bottom: 8px;
          }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>ChatGPT GitHub Integration</h1>
          <p>Download the browser extension to integrate ChatGPT with GitHub repositories</p>
          <a href="/extension/download" class="button">Download Extension</a>
          
          <div class="instructions">
            <h2>Installation Instructions:</h2>
            <ol>
              <li>Download the extension ZIP file</li>
              <li>Unzip the file to a folder on your computer</li>
              <li>Open your browser's extensions page:</li>
              <ul>
                <li>Chrome: chrome://extensions</li>
                <li>Edge: edge://extensions</li>
                <li>Brave: brave://extensions</li>
              </ul>
              <li>Enable "Developer mode" using the toggle in the top-right corner</li>
              <li>Click "Load unpacked" and select the unzipped extension folder</li>
              <li>The ChatGPT GitHub Integration icon should appear in your browser toolbar</li>
              <li>Click the extension icon and enter this server URL: <strong>${req.protocol}://${req.headers.host}</strong></li>
            </ol>
          </div>
        </div>
      </body>
    </html>
  `);
});

// Create endpoint to download the extension as a ZIP file
app.get('/extension/download', async (req, res) => {
  const extensionDir = path.join(__dirname, '../extension');
  const zipFilePath = path.join(__dirname, '../extension.zip');

  // Check if extension directory exists
  try {
    if (!fs.existsSync(extensionDir)) {
      // Create extension directory and necessary files if they don't exist
      await createExtensionFiles();
    }

    // Check if zip file exists
    if (!fs.existsSync(zipFilePath)) {
      // Create a file to stream archive data to
      const output = fs.createWriteStream(zipFilePath);
      const archive = archiver('zip', {
        zlib: { level: 9 } // Maximum compression level
      });

      // Listen for all archive data to be written
      output.on('close', function() {
        logger.info(`Extension ZIP file created: ${archive.pointer()} total bytes`);
        
        // Set headers for file download
        res.set({
          'Content-Type': 'application/zip',
          'Content-Disposition': 'attachment; filename=chatgpt-github-integration.zip'
        });
        
        // Stream the file to the response
        const fileStream = fs.createReadStream(zipFilePath);
        fileStream.pipe(res);
      });

      // Handle errors
      archive.on('error', function(err) {
        logger.error('Error creating ZIP file:', err);
        res.status(500).send('Error creating extension ZIP file');
      });

      // Pipe archive data to the output file
      archive.pipe(output);

      // Add all files from the extension directory to the archive
      archive.directory(extensionDir, false);

      // Finalize the archive
      await archive.finalize();
    } else {
      // Set headers for file download
      res.set({
        'Content-Type': 'application/zip',
        'Content-Disposition': 'attachment; filename=chatgpt-github-integration.zip'
      });
      
      // Stream the file to the response
      const fileStream = fs.createReadStream(zipFilePath);
      fileStream.pipe(res);
    }
  } catch (error) {
    logger.error('Error creating or serving extension ZIP:', error);
    res.status(500).send('Error preparing extension for download');
  }
});

// Helper function to create extension files if they don't exist
async function createExtensionFiles() {
  logger.info('Creating extension files...');
  
  const extensionDir = path.join(__dirname, '../extension');
  const imagesDir = path.join(extensionDir, 'images');
  
  // Create directories
  if (!fs.existsSync(extensionDir)) {
    fs.mkdirSync(extensionDir, { recursive: true });
  }
  
  if (!fs.existsSync(imagesDir)) {
    fs.mkdirSync(imagesDir, { recursive: true });
  }
  
  // Copy extension files from project root if they exist
  const files = [
    'manifest.json',
    'popup.html',
    'popup.js',
    'background.js',
    'content.js',
    'styles.css'
  ];
  
  for (const file of files) {
    const sourcePath = path.join(__dirname, '..', file);
    const destPath = path.join(extensionDir, file);
    
    if (fs.existsSync(sourcePath)) {
      fs.copyFileSync(sourcePath, destPath);
    } else {
      logger.warn(`Warning: Source file ${file} not found`);
    }
  }
  
  // Also copy browser-extension-styles.css as styles.css if the main styles.css doesn't exist
  if (!fs.existsSync(path.join(extensionDir, 'styles.css'))) {
    const sourceStylesPath = path.join(__dirname, '..', 'browser-extension-styles.css');
    if (fs.existsSync(sourceStylesPath)) {
      fs.copyFileSync(sourceStylesPath, path.join(extensionDir, 'styles.css'));
    }
  }
  
  // Download GitHub icons
  await downloadGitHubIcons(imagesDir);
  
  logger.info('Extension files created successfully');
}

// Helper function to download GitHub icons
async function downloadGitHubIcons(imagesDir) {
  const https = require('https');
  const iconUrls = [
    {
      url: 'https://raw.githubusercontent.com/JJP123/simpleicons/master/icons/github/github-16.png',
      filename: 'icon16.png'
    },
    {
      url: 'https://raw.githubusercontent.com/JJP123/simpleicons/master/icons/github/github-48.png',
      filename: 'icon48.png'
    },
    {
      url: 'https://raw.githubusercontent.com/JJP123/simpleicons/master/icons/github/github-128.png',
      filename: 'icon128.png'
    }
  ];
  
  // Create a promise to download each icon
  const downloadPromises = iconUrls.map(icon => {
    return new Promise((resolve, reject) => {
      const file = fs.createWriteStream(path.join(imagesDir, icon.filename));
      
      https.get(icon.url, (response) => {
        if (response.statusCode !== 200) {
          reject(new Error(`Failed to download ${icon.url}: ${response.statusCode}`));
          return;
        }
        
        response.pipe(file);
        
        file.on('finish', () => {
          file.close(resolve);
        });
      }).on('error', (err) => {
        fs.unlink(path.join(imagesDir, icon.filename), () => {});
        reject(err);
      });
    });
  });
  
  // Wait for all icons to download
  try {
    await Promise.all(downloadPromises);
    logger.info('All GitHub icons downloaded successfully');
  } catch (error) {
    logger.error('Error downloading GitHub icons:', error);
    throw error;
  }
}

// Helper functions
function ensureAuthenticated(req, res, next) {
  if (req.isAuthenticated()) {
    return next();
  }
  res.status(401).json({ error: 'Not authenticated' });
}

// Start server
app.listen(PORT, () => {
  logger.info(`Server running on port ${PORT}`);
  console.log(`Server running on port ${PORT}`);
});
EOF

# Make sure the server.js file is created with the enhanced security code
if [ ! -s server/server.js ]; then
  print_error "Failed to create server.js file. Please ensure the file is created manually."
else
  print_success "Server.js file created successfully with enhanced security features."
fi

# Set up automated security updates cron job
print_message "Setting up automated updates..."
(crontab -l 2>/dev/null || echo "") | grep -v "$INSTALL_DIR/update.sh" | { cat; echo "0 2 * * 0 cd $INSTALL_DIR && ./update.sh >> $INSTALL_DIR/data/logs/auto-update.log 2>&1"; } | crontab -
print_success "Weekly automated updates configured for Sunday at 2 AM"

# Build and start Docker containers
print_message "Building and starting Docker containers..."
docker-compose build
docker-compose up -d

# Build extension
print_message "Building extension..."
cd extension
./build-extension.sh
cd ..

print_success "Installation completed successfully with security enhancements!"
print_message "Your secure ChatGPT GitHub Integration is now running at: https://$SERVER_DOMAIN"
print_message "View server logs with: docker-compose logs -f"
print_message "You can access the extension download page at: https://$SERVER_DOMAIN/extension"
print_message "If you need to update the installation in the future, run: ./update.sh"
