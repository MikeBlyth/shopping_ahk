let detectorEnabled = false;

// Function to extract product data
function extractWalmartProductData() {
    const data = {
        walmart_product: true,
        description: null,
        price: null,
        productId: null,
        outOfStock: false
    };

    const descriptionElement = document.getElementById('main-title');
    if (descriptionElement) {
        data.description = descriptionElement.textContent.trim();
    }

    const priceElement = document.querySelector('[itemprop="price"]');
    if (priceElement) {
        const priceText = priceElement.textContent.trim();
        data.price = parseFloat(priceText.replace(/[^0-9.]/g, ''));
        if (isNaN(data.price)) data.price = null;
    }

    // --- Improved Product ID Extraction Logic with Logging ---
    const path = window.location.pathname;
    const urlParams = new URLSearchParams(window.location.search);
    
    let foundProductId = null;
    let foundMethod = null;

    // 1. 'athancid' URL parameter (Primary)
    if (urlParams.has('athancid')) {
        foundProductId = urlParams.get('athancid');
        foundMethod = 'athancid URL parameter';
    }
    // 2. URL Path (/ip/.../12345) (Fallback)
    else if (path.includes('/ip/')) {
        const matches = path.match(/\/(\d+)$/);
        if (matches && matches[1]) {
            foundProductId = matches[1];
            foundMethod = 'URL Path';
        }
    }
    // 3. Meta Tag (if still not found)
    else {
        const ogProductId = document.querySelector('meta[property="og:product:retailer_item_id"]');
        if (ogProductId && ogProductId.content) {
            foundProductId = ogProductId.content;
            foundMethod = 'og:product:retailer_item_id meta tag';
        }
        // 4. 'data-sku' attribute (last resort)
        else {
            const skuElement = document.querySelector('[data-sku]');
            if (skuElement && skuElement.dataset.sku) {
                foundProductId = skuElement.dataset.sku;
                foundMethod = 'data-sku attribute';
            }
        }
    }

    if (foundProductId) {
        data.productId = foundProductId;
        console.log(`Product ID found via ${foundMethod}: ${data.productId}`);
    } else {
        console.warn('Could not find Product ID on page.');
    }
    // --- End of Improved Logic ---

    const addToCartSection = document.querySelector('[data-seo-id="add-to-cart-section"]');
    if (addToCartSection && addToCartSection.textContent.includes('Out of stock')) {
        data.outOfStock = true;
    }

    data.url = window.location.href;
    
    return data;
}

// Function to send data to local server
function sendToLocalServer(data) {
    chrome.runtime.sendMessage({
        action: 'sendToServer',
        data: data
    }, function(response) {
        if (chrome.runtime.lastError) {
            console.error('❌ Error sending message to background:', chrome.runtime.lastError);
        } else {
            console.log('✅ Message sent to background:', response);
        }
    });
}

// Main function to run the detection
function runDetection() {
    if (!detectorEnabled) return;

    const productData = extractWalmartProductData();
    
    // Only send if we found at least a description and price
    if (productData.description && productData.price) {
        sendToLocalServer(productData);
        // Disconnect observer after successfully finding and sending data
        if (observer) {
            observer.disconnect();
            console.log('👀 Observer disconnected after successful detection.');
        }
    }
}

// Listen for messages from the popup
chrome.runtime.onMessage.addListener(function (request, sender, sendResponse) {
    if (request.action === 'updateStatus') {
        detectorEnabled = request.enabled;
        console.log('Detector status updated:', detectorEnabled);
        if (detectorEnabled) {
            runDetection(); // Run detection immediately when enabled
        }
        sendResponse({ status: 'updated' });
    } else if (request.action === 'runTest') {
        const testData = extractWalmartProductData();
        console.log('🧪 Test run data:', testData);
        if (testData.description && testData.price) {
            sendToLocalServer(testData);
            sendResponse({ status: 'Test successful, data sent to server.' });
        } else {
            sendResponse({ status: 'Test failed, could not find product data.' });
        }
    }
});

// Initial load of the enabled state
chrome.storage.local.get(['detectorEnabled'], function (result) {
    detectorEnabled = result.detectorEnabled;
    console.log('Initial detector status:', detectorEnabled);
    if (detectorEnabled === undefined) {
         console.log('Detector status undefined, defaulting to false.');
    }
    if (detectorEnabled) {
        // Since content scripts can load at different times, we use a MutationObserver 
        // to wait for the target elements to appear on the page.
        runDetection();
    }
});


// --- DOM Monitoring ---
const observer = new MutationObserver((mutationsList, observer) => {
    // Look for changes that might indicate the product data is now available.
    // A simple check for the main-title element is a good starting point.
    if (document.getElementById('main-title')) {
        // console.log('Mutation detected main-title, attempting detection...'); // excessive logging commented out
        runDetection();
    }
});

// Start observing the document body for changes
observer.observe(document.body, { childList: true, subtree: true });
console.log('👀 Walmart product data observer started.');
