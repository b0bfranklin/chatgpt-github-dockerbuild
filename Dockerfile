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
