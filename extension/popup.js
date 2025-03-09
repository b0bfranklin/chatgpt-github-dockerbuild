// popup.js
document.addEventListener('DOMContentLoaded', () => {
  // Load server URL from storage
  chrome.storage.sync.get('serverUrl', (data) => {
    if (data.serverUrl) {
      document.getElementById('server-url').value = data.serverUrl;
      checkAuthStatus(data.serverUrl);
    }
  });
  
  // Add event listeners
  document.getElementById('login-button').addEventListener('click', initiateLogin);
  document.getElementById('logout-button').addEventListener('click', logout);
  document.getElementById('save-url-button').addEventListener('click', saveServerUrl);
});

function saveServerUrl() {
  const serverUrl = document.getElementById('server-url').value.trim();
  
  if (!serverUrl) {
    alert('Please enter a valid server URL');
    return;
  }
  
  chrome.storage.sync.set({ serverUrl }, () => {
    alert('Server URL saved successfully');
    checkAuthStatus(serverUrl);
  });
}

function checkAuthStatus(serverUrl) {
  fetch(`${serverUrl}/api/user`, {
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
    updateUIForAuthenticatedUser(user);
  })
  .catch(error => {
    updateUIForUnauthenticatedUser();
  });
}

function initiateLogin() {
  const serverUrl = document.getElementById('server-url').value.trim();
  
  if (!serverUrl) {
    alert('Please enter and save the server URL first');
    return;
  }
  
  chrome.tabs.create({
    url: `${serverUrl}/auth/github`
  });
}

function logout() {
  const serverUrl = document.getElementById('server-url').value.trim();
  
  fetch(`${serverUrl}/auth/logout`, {
    credentials: 'include'
  })
  .then(() => {
    updateUIForUnauthenticatedUser();
  })
  .catch(error => {
    console.error('Error logging out:', error);
  });
}

function updateUIForAuthenticatedUser(user) {
  document.getElementById('status').className = 'status status-connected';
  document.getElementById('status').textContent = 'Connected to GitHub';
  
  document.getElementById('username').textContent = user.username;
  document.getElementById('user-info').style.display = 'block';
  
  document.getElementById('login-button').style.display = 'none';
  document.getElementById('logout-button').style.display = 'block';
}

function updateUIForUnauthenticatedUser() {
  document.getElementById('status').className = 'status status-disconnected';
  document.getElementById('status').textContent = 'Not connected to GitHub';
  
  document.getElementById('user-info').style.display = 'none';
  
  document.getElementById('login-button').style.display = 'block';
  document.getElementById('logout-button').style.display = 'none';
}
