FROM node:18-slim

# Set working directory
WORKDIR /app

# Add non-root user first for better security
RUN useradd -m -s /bin/bash chatgptgit

# Install system dependencies with security in mind
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    redis-server \
    nginx \
    certbot \
    python3-certbot-nginx \
    curl \
    zip \
    openssl \
    ca-certificates \
    gnupg \
    dirmngr \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create application directories with proper permissions
RUN mkdir -p /opt/chatgpt-github-integration/{server,config,logs,cache} \
    && chown -R chatgptgit:chatgptgit /opt/chatgpt-github-integration \
    && chmod 750 /opt/chatgpt-github-integration

# Switch to the application directory
WORKDIR /opt/chatgpt-github-integration/server

# Copy package.json and package-lock.json (if available)
COPY --chown=chatgptgit:chatgptgit server/package*.json ./

# Install Node.js dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy server code
COPY --chown=chatgptgit:chatgptgit server/server.js ./
COPY --chown=chatgptgit:chatgptgit server/.env.example ./.env

# Copy Nginx configuration
COPY nginx/chatgpt-github-integration /etc/nginx/sites-available/
RUN ln -sf /etc/nginx/sites-available/chatgpt-github-integration /etc/nginx/sites-enabled/ \
    && rm -f /etc/nginx/sites-enabled/default \
    && chmod 644 /etc/nginx/sites-available/chatgpt-github-integration

# Create directory for secrets
RUN mkdir -p /run/secrets && chmod 700 /run/secrets

# Create a secure temporary directory
RUN mkdir -p /tmp/app-tmp && chown chatgptgit:chatgptgit /tmp/app-tmp
ENV TMPDIR=/tmp/app-tmp

# Expose ports
EXPOSE 3000 80 443

# Create startup script
COPY --chown=root:root docker-entrypoint.sh /usr/local/bin/
RUN chmod 750 /usr/local/bin/docker-entrypoint.sh

# Set environment variables
ENV NODE_ENV=production \
    PORT=3000 \
    REDIS_URL=redis://localhost:6379 \
    NODE_OPTIONS="--max-old-space-size=512"

# Set user for runtime
USER root

ENTRYPOINT ["docker-entrypoint.sh"]
