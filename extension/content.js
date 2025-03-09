// Initialize once the DOM is fully loaded
document.addEventListener('DOMContentLoaded', initializeGitHubIntegration);

// Or if we're loaded after the page
if (document.readyState === 'complete' || document.readyState === 'interactive') {
  initializeGitHubIntegration();
}

// Global variables
let currentRepo = null;
let currentFile = null;
let currentBranch = 'main';
let serverUrl = '';
let conversationHistory = [];
let currentChatId = null;

function initializeGitHubIntegration() {
  console.log('ChatGPT GitHub Integration Extension initialized');

  // Load server URL from storage
  chrome.storage.sync.get('serverUrl', (data) => {
    if (data.serverUrl) {
      serverUrl = data.serverUrl;
      // Watch for chat interface changes
      observeChatInterface();
      // Check if user is authenticated
      checkAuthStatus();
      // Add GitHub integration UI when the interface is ready
      addGitHubIntegrationUI();
      // Start monitoring conversation for history collection
      startConversationMonitoring();
    }
  });
}

function observeChatInterface() {
  // Observe changes to the chat interface to re-add our UI when needed
  const observer = new MutationObserver((mutations) => {
    // Check if our integration is still present, if not, re-add it
    if (!document.getElementById('github-integration-container')) {
      addGitHubIntegrationUI();
    }
    
    // Extract conversation ID from URL if it changes
    const urlMatch = window.location.href.match(/\/chat(?:\/([a-f0-9-]+))?/);
    if (urlMatch && urlMatch[1] && urlMatch[1] !== currentChatId) {
      currentChatId = urlMatch[1];
      console.log('New conversation detected:', currentChatId);
      conversationHistory = []; // Reset history for new conversation
      startConversationMonitoring();
    }
  });
  
  observer.observe(document.body, { 
    childList: true,
    subtree: true 
  });
}

function checkAuthStatus() {
  fetch(`${serverUrl}/api/user`, {
    method: 'GET',
    credentials: 'include'
  })
  .then(response => {
    if (response.ok) {
      return response.json();
    } else {
      throw new Error('Not authenticated');
    }
  })
  .then(user => {
    console.log('Authenticated as:', user.username);
    updateUIForAuthenticatedUser(user);
  })
  .catch(error => {
    console.log('Not authenticated:', error);
    updateUIForUnauthenticatedUser();
  });
}

function addGitHubIntegrationUI() {
  // Find the textarea where users type their messages
  const targetNode = document.querySelector('form div:has(textarea)');
  
  if (!targetNode) {
    console.log('Target node not found, retrying in 1 second');
    setTimeout(addGitHubIntegrationUI, 1000);
    return;
  }

  // Check if we already added the UI
  if (document.getElementById('github-integration-container')) {
    return;
  }

  // Create GitHub button container
  const githubContainer = document.createElement('div');
  githubContainer.id = 'github-integration-container';
  githubContainer.classList.add('github-integration-container');

  // Create GitHub button
  const githubButton = document.createElement('button');
  githubButton.id = 'github-integration-button';
  githubButton.classList.add('github-integration-button');
  githubButton.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="currentColor" d="M12 2A10 10 0 0 0 2 12c0 4.42 2.87 8.17 6.84 9.5c.5.08.66-.23.66-.5v-1.69c-2.77.6-3.36-1.34-3.36-1.34c-.46-1.16-1.11-1.47-1.11-1.47c-.91-.62.07-.6.07-.6c1 .07 1.53 1.03 1.53 1.03c.87 1.52 2.34 1.07 2.91.83c.09-.65.35-1.09.63-1.34c-2.22-.25-4.55-1.11-4.55-4.92c0-1.11.38-2 1.03-2.71c-.1-.25-.45-1.29.1-2.64c0 0 .84-.27 2.75 1.02c.79-.22 1.65-.33 2.5-.33c.85 0 1.71.11 2.5.33c1.91-1.29 2.75-1.02 2.75-1.02c.55 1.35.2 2.39.1 2.64c.65.71 1.03 1.6 1.03 2.71c0 3.82-2.34 4.66-4.57 4.91c.36.31.69.92.69 1.85V21c0 .27.16.59.67.5C19.14 20.16 22 16.42 22 12A10 10 0 0 0 12 2z"/></svg>';
  githubButton.title = 'GitHub Integration';
  githubButton.addEventListener('click', toggleGitHubPanel);

  // Append button to container
  githubContainer.appendChild(githubButton);

  // Add GitHub panel (initially hidden)
  const githubPanel = document.createElement('div');
  githubPanel.id = 'github-panel';
  githubPanel.classList.add('github-panel', 'github-panel-hidden');
  githubPanel.innerHTML = `
    <div class="github-panel-header">
      <h3>GitHub Integration</h3>
      <button id="github-panel-close">&times;</button>
    </div>
    <div class="github-panel-content">
      <div id="github-auth-section">
        <p>Connect to GitHub to access your repositories</p>
        <button id="github-login-button" class="github-button">Login with GitHub</button>
      </div>
      
      <div id="github-repos-section" style="display: none;">
        <div class="github-user-info">
          <span>Logged in as: </span>
          <span id="github-username"></span>
        </div>
        
        <div class="github-actions">
          <button id="github-new-repo-button" class="github-button">New Repository</button>
        </div>
        
        <div class="github-search">
          <input type="text" id="github-repo-search" placeholder="Search repositories...">
        </div>
        
        <div id="github-repos-list" class="github-repos-list">
          <!-- Repositories will be loaded here -->
        </div>
      </div>
      
      <div id="github-new-repo-section" style="display: none;">
        <div class="github-breadcrumb">
          <button id="github-back-to-repos-from-new">&larr; Back</button>
          <span>Create New Repository</span>
        </div>
        
        <div class="github-form">
          <div class="github-form-group">
            <label for="github-new-repo-name">Repository Name</label>
            <input type="text" id="github-new-repo-name" placeholder="my-new-repo">
          </div>
          
          <div class="github-form-group">
            <label for="github-new-repo-description">Description (optional)</label>
            <input type="text" id="github-new-repo-description" placeholder="Description of your repository">
          </div>
          
          <div class="github-form-group">
            <label>Visibility</label>
            <div class="github-radio-group">
              <label>
                <input type="radio" name="github-repo-visibility" value="public" checked>
                Public
              </label>
              <label>
                <input type="radio" name="github-repo-visibility" value="private">
                Private
              </label>
            </div>
          </div>
          
          <div class="github-form-group github-checkbox-group">
            <label>
              <input type="checkbox" id="github-save-conversation" checked>
              Save current conversation
            </label>
          </div>
          
          <div class="github-form-group github-checkbox-group">
            <label>
              <input type="checkbox" id="github-include-working-dir" checked>
              Include working directory with previous messages
            </label>
          </div>
          
          <button id="github-create-repo-button" class="github-button">Create Repository</button>
        </div>
      </div>
      
      <div id="github-repo-content" style="display: none;">
        <div class="github-breadcrumb">
          <button id="github-back-to-repos">&larr; Back to repos</button>
          <span id="github-current-repo"></span>
        </div>
        
        <div class="github-branch-selector">
          <label>Branch: </label>
          <select id="github-branch-select"></select>
        </div>
        
        <div class="github-path-nav">
          <span id="github-current-path"></span>
        </div>
        
        <div id="github-files-list" class="github-files-list">
          <!-- Files will be loaded here -->
        </div>
      </div>
      
      <div id="github-file-content" style="display: none;">
        <div class="github-breadcrumb">
          <button id="github-back-to-files">&larr; Back to files</button>
          <span id="github-current-file"></span>
        </div>
        
        <div class="github-file-actions">
          <button id="github-insert-file">Insert into prompt</button>
          <button id="github-edit-file">Edit file</button>
        </div>
        
        <pre id="github-file-preview" class="github-file-preview"></pre>
        
        <div id="github-editor-container" style="display: none;">
          <textarea id="github-file-editor" class="github-file-editor"></textarea>
          <div class="github-editor-actions">
            <input type="text" id="github-commit-message" placeholder="Commit message">
            <button id="github-save-file">Commit changes</button>
            <button id="github-cancel-edit">Cancel</button>
          </div>
        </div>
      </div>
    </div>
  `;
  function formatDate(dateString) {
  const date = new Date(dateString);
  const now = new Date();
  const diffTime = Math.abs(now - date);
  const diffDays = Math.floor(diffTime / (1000 * 60 * 60 * 24));
  
  if (diffDays === 0) {
    return 'today';
  } else if (diffDays === 1) {
    return 'yesterday';
  } else if (diffDays < 30) {
    return `${diffDays} days ago`;
  } else {
    return date.toLocaleDateString();
  }
}

function showNewRepoForm() {
  document.getElementById('github-repos-section').style.display = 'none';
  document.getElementById('github-repo-content').style.display = 'none';
  document.getElementById('github-file-content').style.display = 'none';
  document.getElementById('github-new-repo-section').style.display = 'block';
  
  // Clear form fields
  document.getElementById('github-new-repo-name').value = '';
  document.getElementById('github-new-repo-description').value = '';
  document.querySelector('input[name="github-repo-visibility"][value="public"]').checked = true;
}

function createNewRepository() {
  const repoName = document.getElementById('github-new-repo-name').value.trim();
  const repoDescription = document.getElementById('github-new-repo-description').value.trim();
  const isPrivate = document.querySelector('input[name="github-repo-visibility"]:checked').value === 'private';
  const saveConversation = document.getElementById('github-save-conversation').checked;
  const includeWorkingDir = document.getElementById('github-include-working-dir').checked;
  
  if (!repoName) {
    alert('Repository name is required');
    return;
  }
  
  // Disable the create button to prevent multiple clicks
  const createButton = document.getElementById('github-create-repo-button');
  createButton.disabled = true;
  createButton.textContent = 'Creating...';
  
  // Create the repository
  fetch(`${serverUrl}/api/repos`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    credentials: 'include',
    body: JSON.stringify({
      name: repoName,
      description: repoDescription,
      private: isPrivate,
      auto_init: true
    })
  })
  .then(response => {
    if (!response.ok) {
      throw new Error('Failed to create repository');
    }
    return response.json();
  })
  .then(async repo => {
    // If we need to save the conversation
    if (saveConversation) {
      await saveConversationToRepo(repo.owner.login, repo.name, includeWorkingDir);
    }
    
    // Show success message
    createButton.textContent = 'Repository Created!';
    setTimeout(() => {
      createButton.disabled = false;
      createButton.textContent = 'Create Repository';
      
      // Go to the new repository
      loadRepoContents(repo.owner.login, repo.name);
    }, 2000);
  })
  .catch(error => {
    console.error('Error creating repository:', error);
    createButton.disabled = false;
    createButton.textContent = 'Create Repository';
    alert('Error creating repository: ' + error.message);
  });
}

function saveConversationToRepo(owner, repo, includeWorkingDir) {
  if (conversationHistory.length === 0) {
    console.log('No conversation to save');
    return Promise.resolve();
  }
  
  // Get the last assistant message for the README
  const assistantMessages = conversationHistory.filter(msg => msg.role === 'assistant');
  const lastAssistantMessage = assistantMessages[assistantMessages.length - 1];
  
  if (!lastAssistantMessage) {
    console.log('No assistant messages found');
    return Promise.resolve();
  }
  
  // Format README content with the last response
  const readmeContent = 
    `# ${repo}\n\n` +
    lastAssistantMessage.content;
  
  const files = [
    {
      path: 'README.md',
      content: readmeContent
    }
  ];
  
  // If including working directory, add previous messages
  if (includeWorkingDir && conversationHistory.length > 1) {
    // Structure for working directory
    const workingDirFiles = [];
    
    // Create conversation.md with all messages
    const conversationContent = conversationHistory.map(msg => 
      `## ${msg.role.charAt(0).toUpperCase() + msg.role.slice(1)}\n\n${msg.content}\n\n---\n\n`
    ).join('');
    
    workingDirFiles.push({
      path: 'working/conversation.md',
      content: conversationContent
    });
    
    // Extract and save code snippets
    const codeSnippets = extractCodeSnippets(conversationHistory);
    codeSnippets.forEach((snippet, index) => {
      workingDirFiles.push({
        path: `working/code/${snippet.language || 'snippet'}_${index + 1}.${getFileExtension(snippet.language)}`,
        content: snippet.code
      });
    });
    
    // Add working dir files to the main files array
    files.push(...workingDirFiles);
  }
  
  // Commit all files to the repository
  return fetch(`${serverUrl}/api/repos/${owner}/${repo}/batch-create`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    credentials: 'include',
    body: JSON.stringify({
      files: files,
      message: 'Initial commit with conversation content',
      branch: 'main'
    })
  })
  .then(response => {
    if (!response.ok) {
      throw new Error('Failed to save conversation');
    }
    return response.json();
  })
  .then(result => {
    console.log('Conversation saved successfully:', result);
    return result;
  });
}

function extractCodeSnippets(conversation) {
  const snippets = [];
  const codeBlockRegex = /```(\w*)([\s\S]*?)```/g;
  
  conversation.forEach(msg => {
    let match;
    while ((match = codeBlockRegex.exec(msg.content)) !== null) {
      const language = match[1].trim();
      const code = match[2].trim();
      
      if (code) {
        snippets.push({
          language,
          code
        });
      }
    }
  });
  
  return snippets;
}

function getFileExtension(language) {
  const extensions = {
    'javascript': 'js',
    'typescript': 'ts',
    'python': 'py',
    'java': 'java',
    'c': 'c',
    'cpp': 'cpp',
    'csharp': 'cs',
    'php': 'php',
    'html': 'html',
    'css': 'css',
    'json': 'json',
    'yaml': 'yml',
    'markdown': 'md',
    'ruby': 'rb',
    'go': 'go',
    'rust': 'rs',
    'swift': 'swift',
    'kotlin': 'kt',
    'sql': 'sql',
    'shell': 'sh',
    'bash': 'sh',
    'powershell': 'ps1'
  };
  
  return extensions[language] || 'txt';
}

function showRepositoriesList() {
  document.getElementById('github-repos-section').style.display = 'block';
  document.getElementById('github-repo-content').style.display = 'none';
  document.getElementById('github-file-content').style.display = 'none';
  document.getElementById('github-new-repo-section').style.display = 'none';
  
  // Refresh the repositories list
  loadRepositories();
}
  function loadRepoContents(owner, repo, path = '', branch = 'main') {
  currentRepo = { owner, repo, path };
  currentBranch = branch;
  
  // First load branches
  fetch(`${serverUrl}/api/repos/${owner}/${repo}/branches`, {
    credentials: 'include'
  })
  .then(response => response.json())
  .then(branches => {
    const branchSelect = document.getElementById('github-branch-select');
    branchSelect.innerHTML = '';
    
    branches.forEach(branchObj => {
      const option = document.createElement('option');
      option.value = branchObj.name;
      option.textContent = branchObj.name;
      if (branchObj.name === branch) {
        option.selected = true;
      }
      branchSelect.appendChild(option);
    });
    
    // Now load the contents for the selected branch
    return fetch(`${serverUrl}/api/repos/${owner}/${repo}/contents/${path}?branch=${branch}`, {
      credentials: 'include'
    });
  })
  .then(response => response.json())
  .then(contents => {
    displayRepoContents(contents, owner, repo, path);
  })
  .catch(error => {
    console.error('Error loading repository contents:', error);
  });
}

function displayRepoContents(contents, owner, repo, path) {
  document.getElementById('github-repos-section').style.display = 'none';
  document.getElementById('github-repo-content').style.display = 'block';
  document.getElementById('github-file-content').style.display = 'none';
  document.getElementById('github-new-repo-section').style.display = 'none';
  
  document.getElementById('github-current-repo').textContent = `${owner}/${repo}`;
  document.getElementById('github-current-path').textContent = path || '/';
  
  const filesList = document.getElementById('github-files-list');
  filesList.innerHTML = '';
  
  if (Array.isArray(contents)) {
    // Sort by type (directories first)
    contents.sort((a, b) => {
      if (a.type === b.type) {
        return a.name.localeCompare(b.name);
      }
      return a.type === 'dir' ? -1 : 1;
    });
    
    // Add parent directory if not at root
    if (path) {
      const parentPath = path.split('/').slice(0, -1).join('/');
      const parentItem = document.createElement('div');
      parentItem.classList.add('github-file-item', 'github-parent-dir');
      parentItem.innerHTML = `
        <div class="github-file-icon">📁</div>
        <div class="github-file-name">..</div>
      `;
      parentItem.addEventListener('click', () => loadRepoContents(owner, repo, parentPath, currentBranch));
      filesList.appendChild(parentItem);
    }
    
    // Display directories and files
    contents.forEach(item => {
      const fileItem = document.createElement('div');
      fileItem.classList.add('github-file-item');
      
      const icon = item.type === 'dir' ? '📁' : getFileIcon(item.name);
      
      fileItem.innerHTML = `
        <div class="github-file-icon">${icon}</div>
        <div class="github-file-name">${item.name}</div>
      `;
      
      if (item.type === 'dir') {
        fileItem.addEventListener('click', () => {
          const newPath = path ? `${path}/${item.name}` : item.name;
          loadRepoContents(owner, repo, newPath, currentBranch);
        });
      } else {
        fileItem.addEventListener('click', () => {
          loadFileContent(owner, repo, item.path, item.sha);
        });
      }
      
      filesList.appendChild(fileItem);
    });
  } else {
    // Handle single file response
    loadFileContent(owner, repo, contents.path, contents.sha);
  }
}

function loadFileContent(owner, repo, path, sha) {
  currentFile = { owner, repo, path, sha };
  
  fetch(`${serverUrl}/api/repos/${owner}/${repo}/contents/${path}?branch=${currentBranch}`, {
    credentials: 'include'
  })
  .then(response => response.json())
  .then(file => {
    // Display file content
    document.getElementById('github-repo-content').style.display = 'none';
    document.getElementById('github-file-content').style.display = 'block';
    
    const fileName = path.split('/').pop();
    document.getElementById('github-current-file').textContent = fileName;
    
    let content = '';
    if (file.encoding === 'base64') {
      content = atob(file.content);
    } else {
      content = file.content;
    }
    
    document.getElementById('github-file-preview').textContent = content;
    document.getElementById('github-file-editor').value = content;
    
    // Hide editor
    document.getElementById('github-editor-container').style.display = 'none';
    document.getElementById('github-file-preview').style.display = 'block';
  })
  .catch(error => {
    console.error('Error loading file content:', error);
  });
}

function showFilesInCurrentRepo() {
  if (currentRepo) {
    loadRepoContents(currentRepo.owner, currentRepo.repo, currentRepo.path, currentBranch);
  }
}

function changeBranch(event) {
  if (currentRepo) {
    currentBranch = event.target.value;
    loadRepoContents(currentRepo.owner, currentRepo.repo, currentRepo.path, currentBranch);
  }
}

function insertFileContent() {
  const fileContent = document.getElementById('github-file-preview').textContent;
  const textarea = document.querySelector('form textarea');
  
  if (textarea && fileContent) {
    const fileName = currentFile.path.split('/').pop();
    const fileExtension = fileName.split('.').pop().toLowerCase();
    
    let formattedContent = '';
    
    if (['js', 'py', 'java', 'c', 'cpp', 'cs', 'go', 'rb', 'php', 'swift', 'ts', 'sh'].includes(fileExtension)) {
      formattedContent = `\`\`\`${fileExtension}\n${fileContent}\n\`\`\``;
    } else if (['json', 'yaml', 'yml', 'xml', 'html', 'css', 'md', 'sql'].includes(fileExtension)) {
      formattedContent = `\`\`\`${fileExtension}\n${fileContent}\n\`\`\``;
    } else {
      formattedContent = `\`\`\`\n${fileContent}\n\`\`\``;
    }
    
    // Insert at cursor position or append to end
    if (textarea.selectionStart || textarea.selectionStart === 0) {
      const startPos = textarea.selectionStart;
      const endPos = textarea.selectionEnd;
      
      textarea.value = textarea.value.substring(0, startPos) +
        formattedContent +
        textarea.value.substring(endPos, textarea.value.length);
        
      // Set cursor position after the inserted content
      textarea.selectionStart = startPos + formattedContent.length;
      textarea.selectionEnd = startPos + formattedContent.length;
    } else {
      textarea.value += formattedContent;
    }
    
    // Focus the textarea and trigger an input event to update the UI
    textarea.focus();
    textarea.dispatchEvent(new Event('input', { bubbles: true }));
    
    // Close GitHub panel
    toggleGitHubPanel();
  }
}
 function toggleFileEditor() {
  const previewElement = document.getElementById('github-file-preview');
  const editorContainer = document.getElementById('github-editor-container');
  
  previewElement.style.display = 'none';
  editorContainer.style.display = 'block';
}

function cancelFileEdit() {
  const previewElement = document.getElementById('github-file-preview');
  const editorContainer = document.getElementById('github-editor-container');
  
  previewElement.style.display = 'block';
  editorContainer.style.display = 'none';
}

function saveFileChanges() {
  const newContent = document.getElementById('github-file-editor').value;
  const commitMessage = document.getElementById('github-commit-message').value || `Update ${currentFile.path}`;
  
  if (!newContent || !currentFile) {
    return;
  }
  
  fetch(`${serverUrl}/api/repos/${currentFile.owner}/${currentFile.repo}/contents/${currentFile.path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    credentials: 'include',
    body: JSON.stringify({
      content: newContent,
      message: commitMessage,
      sha: currentFile.sha,
      branch: currentBranch
    }) 
