Check the status of all Lumie production services on the server.

## Steps

1. SSH to the server and check all services in one command:

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 << 'EOF'
echo "=== Nginx ==="
sudo systemctl status nginx --no-pager | head -3

echo -e "\n=== Lumie API ==="
sudo systemctl status lumie-api --no-pager | head -3

echo -e "\n=== MongoDB ==="
sudo systemctl status mongod --no-pager | head -3

echo -e "\n=== SSL Certificate ==="
sudo certbot certificates 2>/dev/null | grep "Expiry Date"

echo -e "\n=== Disk Usage ==="
df -h / | tail -1

echo -e "\n=== Memory ==="
free -h | head -2
EOF
```

2. Run a health check: `curl -s https://yumo.org/api/v1/health`

3. Report the results to the user in a clear summary table.
