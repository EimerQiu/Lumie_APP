Deploy the Lumie backend API to the production server.

## Steps

1. Run the deploy script: `bash lumie_backend/deploy.sh`
2. Restart the API service: `ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 "sudo systemctl restart lumie-api"`
3. Wait 3 seconds, then verify the service is running: `ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 "sudo systemctl status lumie-api --no-pager | head -5"`
4. Run a health check: `curl -s https://yumo.org/api/v1/health`
5. Report the result to the user

If any step fails, check the logs: `ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 "sudo journalctl -u lumie-api -n 30 --no-pager"`
