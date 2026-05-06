#!/bin/bash
# Lumie Website Deployment Script
# Deploys static website files to yumo.org

set -e  # Exit on error

# Configuration
SERVER_IP="54.177.85.124"
SERVER_USER="ubuntu"
SSH_KEY="$HOME/.ssh/Lumie_Key.pem"
REMOTE_DIR="/home/ubuntu/website"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================="
echo "Lumie Website Deployment"
echo "========================================="
echo ""

# Check SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    echo "❌ Error: SSH key not found at $SSH_KEY"
    exit 1
fi

echo "📦 Preparing website files..."
cd "$LOCAL_DIR"

echo "✅ Files ready"
echo ""

echo "📤 Uploading to server..."
# Create remote directory if it doesn't exist
ssh -i "$SSH_KEY" "$SERVER_USER@$SERVER_IP" "sudo mkdir -p $REMOTE_DIR"

# Upload website files
echo "  → Uploading HTML files..."
scp -i "$SSH_KEY" *.html "$SERVER_USER@$SERVER_IP:/tmp/"

echo "  → Uploading CSS..."
scp -i "$SSH_KEY" *.css "$SERVER_USER@$SERVER_IP:/tmp/" 2>/dev/null || true

echo "  → Uploading JavaScript..."
scp -i "$SSH_KEY" *.js "$SERVER_USER@$SERVER_IP:/tmp/" 2>/dev/null || true

echo "  → Uploading assets..."
scp -i "$SSH_KEY" -r assets "$SERVER_USER@$SERVER_IP:/tmp/" 2>/dev/null || true

echo "  → Uploading docs..."
scp -i "$SSH_KEY" -r docs "$SERVER_USER@$SERVER_IP:/tmp/" 2>/dev/null || true

echo "✅ Upload complete"
echo ""

echo "🔧 Moving files to web directory..."
ssh -i "$SSH_KEY" "$SERVER_USER@$SERVER_IP" << 'ENDSSH'
set -e

# Move files to web directory
mv /tmp/*.html /home/ubuntu/website/ 2>/dev/null || true
mv /tmp/*.css /home/ubuntu/website/ 2>/dev/null || true
mv /tmp/*.js /home/ubuntu/website/ 2>/dev/null || true
mv /tmp/assets /home/ubuntu/website/ 2>/dev/null || true
mv /tmp/docs /home/ubuntu/website/ 2>/dev/null || true

# Set proper permissions
chown -R ubuntu:ubuntu /home/ubuntu/website
chmod -R 755 /home/ubuntu/website

echo "✅ Files moved successfully"
ENDSSH

echo ""
echo "========================================="
echo "✅ Deployment Complete!"
echo "========================================="
echo ""
echo "Verify the fix:"
echo "  1. Create a test account"
echo "  2. Check verification email"
echo "  3. Click verification link"
echo "  4. Should now successfully verify!"
echo ""
echo "Test URL: https://yumo.org/verify.html?token=test"
echo ""
