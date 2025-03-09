# Automated Deployment Instructions

This guide explains how to use the `deploy.sh` script to automate the deployment of the ChatGPT GitHub Integration on a fresh VM or LXC container.

## Prerequisites

- A Debian or Ubuntu-based VM/LXC container with:
  - At least 2GB RAM
  - 2 CPU cores
  - 10GB storage space
  - Root access
  - Network connection with a static IP

- A domain name pointing to your server's IP address

- GitHub OAuth application credentials:
  - Client ID
  - Client Secret

## Deployment Steps

### Step 1: Download the Deployment Script

SSH into your server and download the deployment script:

```bash
ssh root@your-server-ip
curl -O https://raw.githubusercontent.com/yourusername/chatgpt-github-integration/main/deploy.sh
chmod +x deploy.sh
```

### Step 2: Run the Deployment Script

Execute the script with your GitHub OAuth credentials and domain information:

```bash
./deploy.sh \
  --github-client-id YOUR_GITHUB_CLIENT_ID \
  --github-client-secret YOUR_GITHUB_CLIENT_SECRET \
  --server-domain your-domain.com \
  --email your-email@example.com \
  --enable-ssl
```

Replace:
- `YOUR_GITHUB_CLIENT_ID` with your GitHub OAuth Client ID
- `YOUR_GITHUB_CLIENT_SECRET` with your GitHub OAuth Client Secret
- `your-domain.com` with your actual domain name
- `your-email@example.com` with your email address (required for SSL)

### Step 3: Verify Installation

After the script completes, you should:

1. Check that the server is running:
   ```bash
   docker-compose logs -f
   ```

2. Visit `https://your-domain.com` in your browser to verify the server is responding

3. Visit `https://your-domain.com/extension` to access the extension download page

### Available Options

The deployment script accepts the following parameters:

| Parameter | Description | Required |
|-----------|-------------|----------|
| `--github-client-id` | GitHub OAuth application client ID | Yes |
| `--github-client-secret` | GitHub OAuth application client secret | Yes |
| `--server-domain` | Your server's domain name | Yes |
| `--email` | Your email (for SSL certificate) | Yes, if SSL enabled |
| `--enable-ssl` | Enable HTTPS with Let's Encrypt | No (default: disabled) |
| `--install-dir` | Installation directory | No (default: /opt/chatgpt-github-integration) |

## Updating Your Installation

The deployment script installs an update script that can be used to keep your installation current:

```bash
cd /opt/chatgpt-github-integration
./update.sh
```

This will:
- Back up your current configuration
- Rebuild the Docker containers
- Update the browser extension

## Troubleshooting

If you encounter issues during deployment:

1. Check the script output for error messages
2. Verify that your domain is correctly pointing to your server's IP
3. Ensure ports 80, 443, and 3000 are open on your server
4. Verify your GitHub OAuth credentials are correct
5. Check the Docker container logs for more information:
   ```bash
   docker-compose logs -f
   ```

## Security Considerations

- The script sets up a secure environment, but for production use, consider:
  - Using a firewall to restrict access
  - Setting up regular backups
  - Implementing monitoring
  - Using Docker secrets for sensitive information
