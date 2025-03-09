// Extension ZIP file endpoint
// Add this code to server.js

const fs = require('fs');
const path = require('path');
const archiver = require('archiver');

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

    // Create a file to stream archive data to
    const output = fs.createWriteStream(zipFilePath);
    const archive = archiver('zip', {
      zlib: { level: 9 } // Maximum compression level
    });

    // Listen for all archive data to be written
    output.on('close', function() {
      console.log(`Extension ZIP file created: ${archive.pointer()} total bytes`);
      
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
      console.error('Error creating ZIP file:', err);
      res.status(500).send('Error creating extension ZIP file');
    });

    // Pipe archive data to the output file
    archive.pipe(output);

    // Add all files from the extension directory to the archive
    archive.directory(extensionDir, false);

    // Finalize the archive
    await archive.finalize();
  } catch (error) {
    console.error('Error creating or serving extension ZIP:', error);
    res.status(500).send('Error preparing extension for download');
  }
});

// Helper function to create extension files if they don't exist
async function createExtensionFiles() {
  console.log('Creating extension files...');
  
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
      console.warn(`Warning: Source file ${file} not found`);
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
  
  console.log('Extension files created successfully');
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
    console.log('All GitHub icons downloaded successfully');
  } catch (error) {
    console.error('Error downloading GitHub icons:', error);
    throw error;
  }
}
