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
