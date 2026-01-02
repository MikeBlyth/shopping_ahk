(function() {
    function extractWalmartProductData() {
        const data = {
            walmart_product: true, // Marker to identify data from our extension
            description: null,
            price: null,
            productId: null,
            outOfStock: false
        };

        // 1. Extract Item Description
        const descriptionElement = document.getElementById('main-title');
        if (descriptionElement) {
            data.description = descriptionElement.textContent.trim();
        }

        // 2. Extract Price
        const priceElement = document.querySelector('[itemprop="price"]');
        if (priceElement) {
            const priceText = priceElement.textContent.trim();
            // Remove currency symbols and convert to float
            data.price = parseFloat(priceText.replace(/[^0-9.]/g, ''));
            if (isNaN(data.price)) {
                data.price = null; // Set to null if parsing fails
            }
        }

        // 3. Extract Product ID
        // First, try to find in the URL parameter 'athancid'
        const urlParams = new URLSearchParams(window.location.search);
        if (urlParams.has('athancid')) {
            data.productId = urlParams.get('athancid');
        } else {
            // If not in URL, try to find it in meta tags or other common data attributes
            // This is a common pattern for product IDs in e-commerce sites
            const ogProductId = document.querySelector('meta[property="og:product:retailer_item_id"]');
            if (ogProductId && ogProductId.content) {
                data.productId = ogProductId.content;
            } else {
                const skuElement = document.querySelector('[data-sku]');
                if (skuElement && skuElement.dataset.sku) {
                    data.productId = skuElement.dataset.sku;
                }
            }
        }

        // 4. Detect Out-of-Stock Status
        const addToCartSection = document.querySelector('[data-seo-id="add-to-cart-section"]');
        if (addToCartSection) {
            if (addToCartSection.textContent.includes('Out of stock')) {
                data.outOfStock = true;
            }
        }

        return data;
    }

    const productData = extractWalmartProductData();
    const jsonData = JSON.stringify(productData);

    // Copy to clipboard
    // This part requires interaction with the browser's clipboard API,
    // which usually needs explicit user permission or a secure context (HTTPS)
    // For a userscript or extension, 'GM_setClipboard' (Greasemonkey/Tampermonkey)
    // or 'navigator.clipboard.writeText' (modern browsers, might need user gesture)
    // would be used.
    
    // For userscript (e.g., Tampermonkey), GM_setClipboard is often preferred
    if (typeof GM_setClipboard !== 'undefined') {
        GM_setClipboard(jsonData, 'text');
    } else if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(jsonData).then(function() {
            console.log('Walmart product data copied to clipboard successfully!');
        }).catch(function(err) {
            console.error('Could not copy Walmart product data to clipboard: ', err);
        });
    } else {
        console.warn('Clipboard API not available or permission denied. Could not copy product data.');
        // Fallback for environments without clipboard access (e.g., alert for debugging)
        // alert('Walmart Product Data:\n' + jsonData);
    }

    console.log('Extracted Walmart Product Data:', productData);

})();
