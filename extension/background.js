// Listen for messages from content script
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === 'openGitHubAuth') {
    chrome.windows.create({
      url: request.url,
      type: 'popup',
      width: 800,
      height: 600
    });
    return true;
  }
});

// Listen for authentication success
chrome.webNavigation.onCompleted.addListener((details) => {
  // Match against any domain, as users will configure their own domain
  if (details.url.includes('/success')) {
    // Notify content script that auth is successful
    chrome.tabs.query({url: "https://chat.openai.com/*"}, (tabs) => {
      if (tabs.length > 0) {
        chrome.tabs.sendMessage(tabs[0].id, {
          action: 'authSuccess'
        });
      }
      
      // Close the auth tab
      chrome.tabs.remove(details.tabId);
    });
  }
}, {url: [{urlContains: '/success'}]});
