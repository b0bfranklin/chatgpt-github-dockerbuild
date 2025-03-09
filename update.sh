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
  for file in manifest.json popup.html popup.js background.js content.js styles.css browser-extension-styles.css; do
    if [ -f $file ]; then
      cp $file $BACKUP_DIR/extension_source/
    fi
  done
  
  print_success "Backup created in directory: $BACKUP_DIR"
}

# Pull latest changes from git repository
pull_latest_changes() {
  print_message "Checking for updates..."
  
  # Check if we're in a git repository
  if [ -d .git ]; then
    # Save current branch
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    
    # Fetch latest changes
    git fetch
    
    # Check if we're behind the remote
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse @{u})
    
    if [ $LOCAL = $REMOTE ]; then
      print_message "Already up-to-date."
    else
      print_message "Updates available. Pulling latest changes..."
      git pull
      print_success "Latest changes pulled successfully."
    fi
  else
    print_warning "Not a git repository. Skipping git update."
    print_message "To update manually, download the latest files and replace the existing ones."
  fi
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
  chmod +x build-extension.sh
  
  # Run the extension build script
  ./build-extension.sh
  
  print_success "Browser extension updated."
  print_message "Remember to reload the extension in your browser:"
  print_message "1. Go to your browser's extension management page"
  print_message "2. Find the ChatGPT GitHub Integration extension"
  print_message "3. Click the reload button or toggle it off and on"
}

# Check for configuration changes
check_config_changes() {
  print_message "Checking for configuration changes..."
  
  # Check if docker-compose.yml has changed
  if [ -f $BACKUP_DIR/docker-compose.yml ]; then
    if ! cmp -s docker-compose.yml $BACKUP_DIR/docker-compose.yml; then
      print_warning "The docker-compose.yml file has changed."
      print_message "You may need to update your configuration accordingly."
    fi
  fi
  
  # Check if the example .env file has changed
  if [ -f server/.env.example ]; then
    print_message "Review server/.env.example for any new environment variables that might have been added."
  fi
}

# Main function
main() {
  print_message "Starting ChatGPT GitHub Integration update..."
  
  check_prerequisites
  backup_config
  pull_latest_changes
  update_docker_containers
  update_browser_extension
  check_config_changes
  
  print_success "Update completed successfully!"
  print_message "To verify the update, check the server logs:"
  print_message "docker-compose logs -f"
}

# Run the main function
main
