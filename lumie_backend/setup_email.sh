#!/bin/bash

# Setup Email Service for Lumie Backend
# This script installs dependencies and prepares the server for email sending

set -e  # Exit on error

SERVER="ubuntu@54.193.153.37"
SSH_KEY="~/.ssh/Lumie_Key.pem"
BACKEND_DIR="/home/ubuntu/lumie_backend"

echo "======================================================"
echo "Lumie Email Service Setup"
echo "======================================================"
echo ""

echo "📦 Step 1: Installing Google API dependencies..."
ssh -i $SSH_KEY $SERVER << 'EOF'
cd /home/ubuntu/lumie_backend
source venv/bin/activate

# Install Google API packages
pip install --upgrade google-api-python-client google-auth google-auth-httplib2 google-auth-oauthlib

echo "✅ Dependencies installed"
EOF

echo ""
echo "📁 Step 2: Creating secrets directory..."
ssh -i $SSH_KEY $SERVER << 'EOF'
mkdir -p /home/ubuntu/secrets
chmod 700 /home/ubuntu/secrets
echo "✅ Secrets directory created at /home/ubuntu/secrets"
EOF

echo ""
echo "📤 Step 3: Uploading email service files..."
scp -i $SSH_KEY app/services/email_service.py $SERVER:$BACKEND_DIR/app/services/
scp -i $SSH_KEY test_email.py $SERVER:$BACKEND_DIR/

echo "✅ Email service files uploaded"

echo ""
echo "======================================================"
echo "✅ Email Service Setup Complete!"
echo "======================================================"
echo ""
echo "📝 Next Steps:"
echo ""
echo "1. Upload Service Account Key:"
echo "   scp -i ~/.ssh/Lumie_Key.pem /path/to/lumie-mailer.json ubuntu@54.193.153.37:/home/ubuntu/secrets/"
echo ""
echo "2. Set Environment Variables (optional):"
echo "   ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37"
echo "   echo 'GMAIL_SERVICE_ACCOUNT_FILE=/home/ubuntu/secrets/lumie-mailer.json' >> /home/ubuntu/lumie_backend/.env"
echo "   echo 'GMAIL_SENDER_EMAIL=lumie@yumo.org' >> /home/ubuntu/lumie_backend/.env"
echo ""
echo "3. Test Email Service:"
echo "   ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37"
echo "   cd /home/ubuntu/lumie_backend"
echo "   source venv/bin/activate"
echo "   python test_email.py"
echo ""
echo "======================================================"
