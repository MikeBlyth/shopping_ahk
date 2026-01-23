chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === 'sendToServer') {
        console.log('📤 Background script sending data to server...', request.data);
        
        fetch('http://127.0.0.1:4567/walmart_product', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(request.data)
        })
        .then(response => {
            console.log('📡 Server responded with status:', response.status);
            return response.json();
        })
        .then(result => {
            console.log('✅ Success result from server:', result);
            sendResponse({status: 'success', data: result});
        })
        .catch(error => {
            console.error('❌ Fetch error in background script:', error);
            sendResponse({status: 'error', error: error.toString()});
        });
        
        return true; // Keep the message channel open for async response
    }
});
