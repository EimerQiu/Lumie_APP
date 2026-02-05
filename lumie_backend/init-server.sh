#!/bin/bash
# Initialize server for Lumie Backend (one-time setup)
# Run this script on the server after first deployment

set -e

echo "========================================="
echo "Lumie Backend Server Initialization"
echo "========================================="
echo ""

# Check if running on server
if [ ! -d "/home/ubuntu" ]; then
    echo "❌ This script should be run on the server"
    echo "Run: ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37"
    echo "Then: cd /home/ubuntu/lumie_backend && bash init-server.sh"
    exit 1
fi

echo "📦 Step 1: Installing system dependencies..."
sudo apt update
sudo apt install -y python3-pip python3-venv

echo ""
echo "🐘 Step 2: Installing MongoDB..."
if ! command -v mongod &> /dev/null; then
    echo "  → MongoDB not found, installing..."

    # Import MongoDB public GPG key
    sudo apt-get install -y gnupg curl
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
       sudo gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg \
       --dearmor

    # Create list file for MongoDB
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" | \
       sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list

    # Install MongoDB
    sudo apt-get update
    sudo apt-get install -y mongodb-org

    # Start and enable MongoDB
    sudo systemctl start mongod
    sudo systemctl enable mongod

    echo "  ✅ MongoDB installed and started"
else
    echo "  ✅ MongoDB already installed"
    sudo systemctl start mongod || true
    sudo systemctl enable mongod || true
fi

echo ""
echo "🔐 Step 3: Setting up environment variables..."
if [ ! -f "/home/ubuntu/lumie_backend/.env" ]; then
    echo "  → Creating .env file from template..."
    cp .env.production .env

    # Generate secure secret key
    SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
    sed -i "s/CHANGE_THIS_TO_SECURE_RANDOM_KEY_IN_PRODUCTION/$SECRET_KEY/" .env

    echo "  ⚠️  Please review and update .env file with your settings:"
    echo "     nano /home/ubuntu/lumie_backend/.env"
else
    echo "  ✅ .env file already exists"
fi

echo ""
echo "🔧 Step 4: Setting up systemd service..."
sudo cp lumie-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable lumie-api

echo ""
echo "🌐 Step 5: Setting up Nginx..."
sudo cp nginx-api.conf /etc/nginx/sites-available/lumie-api

# Create symlink if it doesn't exist
if [ ! -L /etc/nginx/sites-enabled/lumie-api ]; then
    sudo ln -s /etc/nginx/sites-available/lumie-api /etc/nginx/sites-enabled/
fi

# Test Nginx configuration
sudo nginx -t

echo ""
echo "========================================="
echo "✅ Server Initialization Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Review and update environment variables:"
echo "   nano /home/ubuntu/lumie_backend/.env"
echo ""
echo "2. Add DNS A record:"
echo "   api.yumo.org → 54.193.153.37"
echo ""
echo "3. Get SSL certificate (after DNS propagates):"
echo "   sudo certbot certonly --nginx -d api.yumo.org"
echo "   Then update nginx-api.conf with the certificate path if needed"
echo ""
echo "4. Start the API:"
echo "   sudo systemctl start lumie-api"
echo "   sudo systemctl reload nginx"
echo ""
echo "5. Check status:"
echo "   sudo systemctl status lumie-api"
echo "   curl http://localhost:8000/health"
echo ""
echo "6. View logs:"
echo "   sudo journalctl -u lumie-api -f"
echo ""
