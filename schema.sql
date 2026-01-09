-- Walmart Grocery Database Schema
-- Created for tracking grocery items and purchase history

-- Items table: stores grocery item details and URLs
CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    prod_id VARCHAR(50) UNIQUE NOT NULL,     -- Extracted from Walmart URL
    url TEXT NOT NULL,                       -- Full Walmart product URL
    description TEXT NOT NULL,               -- Item description/name
    modifier TEXT,                           -- Size, brand, or other modifier
    default_quantity INTEGER DEFAULT 1,      -- Default quantity to purchase
    priority INTEGER DEFAULT 0,              -- Shopping priority (higher = more important)
    status VARCHAR(20) DEFAULT 'active',     -- 'active' or 'inactive'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Purchases table: tracks purchase history
CREATE TABLE IF NOT EXISTS purchases (
    id SERIAL PRIMARY KEY,
    prod_id VARCHAR(50) NOT NULL REFERENCES items(prod_id),
    purchase_date DATE NOT NULL DEFAULT CURRENT_DATE,
    quantity INTEGER NOT NULL DEFAULT 1,
    price_cents INTEGER,                     -- Price in cents to avoid decimal issues
    purchase_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_items_prod_id ON items(prod_id);
CREATE INDEX IF NOT EXISTS idx_purchases_prod_id ON purchases(prod_id);
CREATE INDEX IF NOT EXISTS idx_purchases_date ON purchases(purchase_date);
CREATE INDEX IF NOT EXISTS idx_items_priority ON items(priority DESC);

-- Create a function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger to automatically update updated_at on items
CREATE TRIGGER update_items_updated_at 
    BEFORE UPDATE ON items 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Sample data for testing (optional)
INSERT INTO items (prod_id, url, description, modifier, default_quantity, priority) 
VALUES 
    ('123456789', 'https://www.walmart.com/ip/Great-Value-2-Milk-1-Gallon/123456789', '2% Milk', '1 Gallon', 1, 9),
    ('987654321', 'https://www.walmart.com/ip/Wonder-Bread-Classic-White/987654321', 'White Bread', 'Classic', 1, 8),
    ('555666777', 'https://www.walmart.com/ip/Large-Eggs-Dozen/555666777', 'Large Eggs', 'Dozen', 1, 7)
ON CONFLICT (prod_id) DO NOTHING;