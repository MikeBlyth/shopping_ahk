document.addEventListener('DOMContentLoaded', function () {
  const toggleButton = document.getElementById('toggleButton');
  const testButton = document.getElementById('testButton');

  // Load the saved state
  chrome.storage.local.get(['detectorEnabled'], function (result) {
    updateButton(result.detectorEnabled);
  });

  // Toggle button click listener
  toggleButton.addEventListener('click', function () {
    chrome.storage.local.get(['detectorEnabled'], function (result) {
      const newStatus = !result.detectorEnabled;
      chrome.storage.local.set({ detectorEnabled: newStatus }, function () {
        updateButton(newStatus);
        // Send a message to the content script to update its status
        sendMessageToContentScript({ action: 'updateStatus', enabled: newStatus });
      });
    });
  });
  
  // Test button click listener
  testButton.addEventListener('click', function() {
    sendMessageToContentScript({ action: 'runTest' });
  });

  // Function to update the button's appearance
  function updateButton(enabled) {
    if (enabled) {
      toggleButton.textContent = 'Disable Detector';
      toggleButton.classList.remove('disabled');
      toggleButton.classList.add('enabled');
    } else {
      toggleButton.textContent = 'Enable Detector';
      toggleButton.classList.remove('enabled');
      toggleButton.classList.add('disabled');
    }
  }

  // Function to send a message to the active tab's content script
  function sendMessageToContentScript(message) {
    chrome.tabs.query({ active: true, currentWindow: true }, function (tabs) {
      if (tabs.length > 0) {
        chrome.tabs.sendMessage(tabs[0].id, message, function (response) {
          if (chrome.runtime.lastError) {
            console.error(chrome.runtime.lastError.message);
          } else {
            console.log(response);
          }
        });
      }
    });
  }
});
