chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === 'sendToServer') {
        fetch('http://127.0.0.1:4567/walmart_product', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(request.data)
        })
        .then(response => response.json())
        .then(result => {
            console.log('✅ Data sent to server:', result);
            sendResponse({status: 'success', data: result});
        })
        .catch(error => {
            console.error('❌ Error sending to server:', error);
            sendResponse({status: 'error', error: error.toString()});
        });
        
        return true; // Keep the message channel open for async response
    }
});
