#!/bin/bash
# Lumie Backend Deployment Script
# Usage: ./deploy.sh

set -e  # Exit on error

# Configuration
SERVER_IP="54.193.153.37"
SERVER_USER="ubuntu"
SSH_KEY="$HOME/.ssh/Lumie_Key.pem"
REMOTE_DIR="/home/ubuntu/lumie_backend"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================="
echo "Lumie Backend Deployment"
echo "========================================="
echo ""

# Check SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    echo "❌ Error: SSH key not found at $SSH_KEY"
    exit 1
fi

echo "📦 Step 1: Preparing backend files..."
cd "$LOCAL_DIR"

# Create deployment package (exclude unnecessary files)
echo "Creating deployment archive..."
tar -czf /tmp/lumie_backend.tar.gz \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.env' \
    --exclude='venv' \
    --exclude='.git' \
    --exclude='*.log' \
    --exclude='deploy.sh' \
    --exclude='lumie-api.service' \
    --exclude='nginx-api.conf' \
    .

echo "✅ Archive created"
echo ""

echo "📤 Step 2: Uploading to server..."
# Create remote directory if it doesn't exist
ssh -i "$SSH_KEY" "$SERVER_USER@$SERVER_IP" "mkdir -p $REMOTE_DIR"

# Upload the archive
scp -i "$SSH_KEY" /tmp/lumie_backend.tar.gz "$SERVER_USER@$SERVER_IP:/tmp/"

echo "✅ Upload complete"
echo ""

echo "🔧 Step 3: Setting up backend on server..."
ssh -i "$SSH_KEY" "$SERVER_USER@$SERVER_IP" << 'ENDSSH'
set -e

echo "  → Extracting files..."
cd /home/ubuntu/lumie_backend
tar -xzf /tmp/lumie_backend.tar.gz -C . 2>/dev/null || true
rm /tmp/lumie_backend.tar.gz

echo "  → Setting up Python virtual environment..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

echo "  → Installing dependencies..."
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo "  → Checking MongoDB..."
if ! systemctl is-active --quiet mongod; then
    echo "  ⚠️  MongoDB is not running. You may need to install and start it."
else
    echo "  ✅ MongoDB is running"
fi

echo "✅ Backend setup complete"
ENDSSH

echo ""
echo "========================================="
echo "✅ Deployment Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Setup environment variables:"
echo "   ssh -i $SSH_KEY $SERVER_USER@$SERVER_IP"
echo "   cd $REMOTE_DIR"
echo "   nano .env  # Configure your environment variables"
echo ""
echo "2. Setup systemd service (one-time):"
echo "   sudo cp lumie-api.service /etc/systemd/system/"
echo "   sudo systemctl daemon-reload"
echo "   sudo systemctl enable lumie-api"
echo "   sudo systemctl start lumie-api"
echo ""
echo "3. Setup Nginx (one-time):"
echo "   sudo cp nginx-api.conf /etc/nginx/sites-available/lumie-api"
echo "   sudo ln -s /etc/nginx/sites-available/lumie-api /etc/nginx/sites-enabled/"
echo "   sudo nginx -t"
echo "   sudo systemctl reload nginx"
echo ""
echo "4. Add DNS record for api.yumo.org → $SERVER_IP"
echo ""
echo "5. Get SSL certificate:"
echo "   sudo certbot certonly --nginx -d api.yumo.org"
echo ""
echo "Useful commands:"
echo "  - Check API status: sudo systemctl status lumie-api"
echo "  - View logs: sudo journalctl -u lumie-api -f"
echo "  - Restart API: sudo systemctl restart lumie-api"
echo "  - Test API: curl https://api.yumo.org/health"
echo ""
