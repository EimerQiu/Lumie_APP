Deploy the Lumie backend API to the production server.

## Steps

1. Run the deploy script: `bash lumie_backend/deploy.sh`
2. Optional: enable debug logs for API (for full proactive prompt logs):
   - `ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 "grep -q '^LOG_LEVEL=' /home/ubuntu/lumie_backend/.env && sed -i 's/^LOG_LEVEL=.*/LOG_LEVEL=DEBUG/' /home/ubuntu/lumie_backend/.env || echo 'LOG_LEVEL=DEBUG' | sudo tee -a /home/ubuntu/lumie_backend/.env >/dev/null"`
3. Restart the API service: `ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 "sudo systemctl restart lumie-api"`
4. Wait 3 seconds, then verify the service is running: `ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 "sudo systemctl status lumie-api --no-pager | head -5"`
5. Run a health check: `curl -s https://yumo.org/api/v1/health`
6. Verify debug logs are active (optional): `ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 "sudo journalctl -u lumie-api -n 50 --no-pager | grep -n 'Logging configured level=' | tail -n 1"`
7. Report the result to the user

## Revert To INFO Logs

When debugging is done, reduce log volume:

- `ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 "grep -q '^LOG_LEVEL=' /home/ubuntu/lumie_backend/.env && sed -i 's/^LOG_LEVEL=.*/LOG_LEVEL=INFO/' /home/ubuntu/lumie_backend/.env || echo 'LOG_LEVEL=INFO' | sudo tee -a /home/ubuntu/lumie_backend/.env >/dev/null"`
- `ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 "sudo systemctl restart lumie-api"`

If any step fails, check the logs: `ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 "sudo journalctl -u lumie-api -n 30 --no-pager"`
