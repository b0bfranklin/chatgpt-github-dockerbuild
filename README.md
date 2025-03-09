# Docker Setup for ChatGPT-GitHub Integration

This repository contains Docker configurations for running the ChatGPT-GitHub Integration server component with built-in extension distribution capabilities. This integration allows you to save ChatGPT conversations directly to GitHub repositories.

## Project Structure

```
.
├── Dockerfile                    # Docker image definition for the server
├── docker-compose.yml            # Docker Compose configuration
├── docker-entrypoint.sh          # Startup script for the container
├── update.sh                     # Script to update the installation
├── extension.zip                 # Packaged browser extension (generated)
├── nginx/                        # Nginx configuration files
│   └── chatgpt-github-integration # Nginx site configuration
├── server/                       # Server component files
│   ├── package.json              # Node.js dependencies
│   ├── server.js                 # Main server code with extension distribution functionality
│   └── .env.example              # Environment variables template
├── extension/                    # Extension files
│   ├── build-extension.sh        # Script to prepare and package extension files
│   ├── images/                   # Extension icons (generated)
│   │   ├── icon16.png            # Small GitHub icon
│   │   ├── icon48.png            # Medium GitHub icon
│   │   └── icon128.png           # Large GitHub icon
│   ├── manifest.json             # Extension manifest
│   ├── popup.html                # Extension popup HTML
│   ├── popup.js                  # Extension popup JavaScript
│   ├── background.js             # Extension background script
│   ├── content.js                # Extension content script
│   └── styles.css                # Extension styles
└── README.md                     # This file
```

## Getting Started

### Prerequisites

- Docker
- Docker Compose
- GitHub OAuth Application credentials

## How to Use with Docker

This project uses Docker Compose to manage the container ecosystem. Here's a complete guide to get everything up and running from scratch:

### Step 1: Install Docker and Docker Compose

**For Ubuntu/Debian:**
```bash
# Install Docker
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get install -y docker-ce

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Add your user to the docker group to run docker without sudo
sudo usermod -aG docker $USER
# Log out and log back in for this to take effect
```

**For macOS:**
```bash
# Install Docker Desktop which includes both Docker and Docker Compose
brew install --cask docker
# Then launch Docker Desktop from your Applications folder
```

**For Windows:**
- Download and install Docker Desktop from [Docker Hub](https://hub.docker.com/editions/community/docker-ce-desktop-windows/)
- Docker Compose is included with Docker Desktop for Windows

### Step 2: Clone this Repository

```bash
git clone https://github.com/yourusername/chatgpt-github-integration.git
cd chatgpt-github-integration
```

### Step 3: Build and Start the Docker Container

```bash
# Build the Docker image
docker-compose build

# Start the containers in detached mode
docker-compose up -d
```

This command does several things:
- Builds the Docker image defined in the Dockerfile
- Creates a container for the server
- Sets up Redis for session management
- Configures Nginx as a reverse proxy
- Applies your environment variables

### Step 4: Check if the Container is Running

```bash
# Check container status
docker-compose ps

# View server logs
docker-compose logs -f server
```

### Step 5: Build the Browser Extension

```bash
# Make the build script executable
chmod +x extension/build-extension.sh

# Run the build script to prepare extension files
cd extension
./build-extension.sh
cd ..
```

### Step 6: Managing the Docker Container

```bash
# Stop the container
docker-compose stop

# Start the container again
docker-compose start

# Restart the container
docker-compose restart

# Stop and remove the container
docker-compose down

# Stop and remove the container along with volumes
docker-compose down -v
```

### Setting Up GitHub OAuth

Before starting the server, you need to create a GitHub OAuth application:

1. Go to GitHub and register a new OAuth application:
   - Navigate to GitHub → Settings → Developer Settings → OAuth Apps → New OAuth App
   - Fill in the application details:
     - Application name: `ChatGPT GitHub Integration`
     - Homepage URL: `https://your-server-domain.com`
     - Authorization callback URL: `https://your-server-domain.com/auth/github/callback`
   - Click "Register application"

2. After registration, you'll get a Client ID and you can generate a Client Secret.

### Environment Setup

Create a `.env` file in the root directory with the following content:

```
SERVER_DOMAIN=your-server-domain.com
GITHUB_CLIENT_ID=your_github_client_id
GITHUB_CLIENT_SECRET=your_github_client_secret
ENABLE_SSL=false
EMAIL_ADDRESS=your-email@example.com
```

- Replace `your-server-domain.com` with your actual domain
- Replace `your_github_client_id` and `your_github_client_secret` with your GitHub OAuth credentials
- Set `ENABLE_SSL` to `true` if you want to enable HTTPS with Let's Encrypt
- Provide your email address for Let's Encrypt notifications

### Running the Server

```bash
# Start the server
docker-compose up -d

# View logs
docker-compose logs -f
```

## Browser Extension Distribution

The server includes a built-in extension distribution system, allowing users to download the browser extension directly from your server.

### Accessing the Extension Download Page

Once your server is running, users can access the extension download page at:

```
https://your-server-domain.com/extension
```

This page provides:
- A download button for the extension ZIP file
- Installation instructions specific to your server
- Step-by-step guidance for installing the extension in various browsers

### How It Works

The extension distribution system works by:

1. Creating a `/extension` endpoint that serves an HTML page with download instructions
2. Providing a `/extension/download` endpoint that generates and serves a ZIP file of the extension
3. Automatically building the extension files if they don't exist
4. Setting the correct headers for browser download

### Extension File Structure

The extension consists of the following files:

- `manifest.json`: Defines extension properties, permissions and entry points
- `popup.html`: HTML for the extension popup
- `popup.js`: JavaScript for the extension popup
- `background.js`: Background script for the extension
- `content.js`: Content script that injects into ChatGPT
- `styles.css`: CSS styles for the extension UI
- `images/`: Directory containing icons in different sizes

### Building the Extension Manually

If you prefer to create the extension files manually:

```bash
cd extension
chmod +x build-extension.sh
./build-extension.sh
```

This will:
1. Ensure all necessary extension files are present
2. Download GitHub icons from the specified repositories if needed
3. Generate an `extension.zip` file in the parent directory for distribution

## Updating Your Installation

You can easily update your ChatGPT GitHub Integration to the latest version using the provided update script.

### Automatic Update

1. Make sure you're in the project directory:
   ```bash
   cd chatgpt-github-integration
   ```

2. Make the update script executable:
   ```bash
   chmod +x update.sh
   ```

3. Run the update script:
   ```bash
   ./update.sh
   ```

The script performs the following actions:
- Creates a backup of your current configuration
- Pulls the latest changes from the repository
- Rebuilds the Docker container with the updated code
- Updates the browser extension files
- Verifies configuration changes

### Manual Update

If you prefer to update manually, follow these steps:

1. Back up your configuration:
   ```bash
   mkdir backup
   cp .env docker-compose.yml backup/
   cp -r nginx backup/
   ```

2. Pull the latest changes:
   ```bash
   git pull
   ```

3. Rebuild and restart the Docker containers:
   ```bash
   docker-compose down
   docker-compose build --no-cache
   docker-compose up -d
   ```

4. Update the browser extension:
   ```bash
   cd extension
   ./build-extension.sh
   cd ..
   ```

5. Reload the extension in your browser

### Post-Update Steps

After updating, you should:

1. Check the logs to verify everything is working:
   ```bash
   docker-compose logs -f
   ```

2. Reload the browser extension in your browser's extension management page

3. Test the functionality by connecting to GitHub and creating a test repository

## Configuration Options

### Environment Variables

- `SERVER_DOMAIN`: Your server's domain name
- `GITHUB_CLIENT_ID`: GitHub OAuth application client ID
- `GITHUB_CLIENT_SECRET`: GitHub OAuth application client secret
- `CLIENT_ORIGIN`: Origin for CORS (default: https://chat.openai.com)
- `ENABLE_SSL`: Whether to enable HTTPS with Let's Encrypt
- `EMAIL_ADDRESS`: Email for Let's Encrypt notifications

## Secure Production Deployment

For production deployments, consider:

1. Always enable SSL (`ENABLE_SSL=true`)
2. Use a strong, random session secret
3. Set up proper firewalls to only expose necessary ports
4. Use Docker secrets for sensitive information

## Troubleshooting

### Server Issues

If the server isn't working correctly:

1. Check container logs:
   ```bash
   docker-compose logs server
   ```

2. Make sure GitHub OAuth credentials are correctly set up
3. Ensure your domain is properly pointing to your server's IP address
4. Check if ports 80, 443, and 3000 are open

### Docker-Specific Issues

1. **Container won't start:**
   ```bash
   # Check for error messages
   docker-compose logs
   
   # Make sure nothing else is using the required ports
   sudo lsof -i :80
   sudo lsof -i :443
   sudo lsof -i :3000
   ```

2. **Permission issues:**
   ```bash
   # Fix permissions on the data directory
   sudo chown -R 1000:1000 ./data
   
   # Check SELinux context if applicable
   sudo chcon -Rt container_file_t ./data
   ```

3. **Network issues:**
   ```bash
   # Check if Docker network is created properly
   docker network ls
   
   # Inspect the network
   docker network inspect chatgpt-github-integration_chatgpt-github-net
   ```

4. **Redis not starting:**
   ```bash
   # Check Redis logs
   docker-compose exec server redis-cli ping
   
   # If Redis isn't responding, restart the container
   docker-compose restart server
   ```

5. **Rebuild from scratch:**
   ```bash
   # If all else fails, rebuild everything from scratch
   docker-compose down -v
   docker-compose build --no-cache
   docker-compose up -d
   ```

### Extension Issues

If the extension isn't connecting to the server:

1. Make sure the server URL is correctly set in the extension
2. Check browser console for any JavaScript errors
3. Ensure the extension has proper permissions
