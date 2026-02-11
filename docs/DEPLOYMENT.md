# Yumo.org Website Deployment Guide

**Live Website:** https://yumo.org
**Redirect Domain:** yumo.life → yumo.org

---

## 🎉 Current Status

### Website
**Website:** 🟢 Live at https://yumo.org
**SSL Certificate:** 🟢 Active (auto-renewal enabled)
**DNS:** 🟢 Configured on GoDaddy
**Redirect:** 🟢 yumo.life → yumo.org

### Backend API
**API Endpoint:** 🟢 Live at http://54.193.153.37:8000
**Service:** 🟢 lumie-api.service (systemd)
**Workers:** 🟢 4 uvicorn workers running
**Database:** 🟢 MongoDB 8.0 running
**Health Check:** 🟢 http://54.193.153.37:8000/api/v1/health

---

## Server Information

**Primary Domain:** yumo.org
**Redirect Domain:** yumo.life (redirects to yumo.org)

**Server Details:**
- **IP Address:** 54.193.153.37
- **Server OS:** Ubuntu 24.04
- **Web Server:** Nginx 1.24.0
- **SSH Key:** `~/.ssh/Lumie_Key.pem`
- **User:** ubuntu

**Website Location:**
- **Web Root:** `/home/ubuntu/website`
- **Nginx Config (yumo.org):** `/etc/nginx/sites-available/yumo.org`
- **Nginx Config (yumo.life):** `/etc/nginx/sites-available/yumo.life`

**Security:**
- **SSL Certificate:** Let's Encrypt (bundled)
- **Certificate Path:** `/etc/letsencrypt/live/yumo-bundle/`
- **Auto-Renewal:** ✅ Enabled
- **HTTPS Redirect:** ✅ Active for both domains
- **HTTP/2:** ✅ Enabled
- **Caching:** ⚠️ Disabled (DEV mode)

---

## DNS Configuration

### yumo.org (Primary Domain)

Configure these A records on GoDaddy for yumo.org:

| Type | Name | Value | TTL |
|------|------|-------|-----|
| A | @ | 54.193.153.37 | 1800 |
| A | www | 54.193.153.37 | 1800 |

### yumo.life (Redirect Domain)

Configure these A records on GoDaddy for yumo.life:

| Type | Name | Value | TTL |
|------|------|-------|-----|
| A | @ | 54.193.153.37 | 1800 |
| A | www | 54.193.153.37 | 1800 |

**Behavior:**
- http://yumo.org → https://yumo.org ✅
- http://www.yumo.org → https://yumo.org ✅
- https://www.yumo.org → https://yumo.org ✅
- http://yumo.life → https://yumo.org ✅
- https://yumo.life → https://yumo.org ✅
- http://www.yumo.life → https://yumo.org ✅
- https://www.yumo.life → https://yumo.org ✅

---

## Nginx Configuration

### yumo.org Configuration

**File:** `/etc/nginx/sites-available/yumo.org`

**Features:**
- HTTP → HTTPS redirect
- www → apex redirect (www.yumo.org → yumo.org)
- Serves content from `/home/ubuntu/website`
- **DEV mode:** Caching disabled for quick updates
- Gzip compression enabled
- Security headers enabled

### yumo.life Configuration

**File:** `/etc/nginx/sites-available/yumo.life`

**Features:**
- All traffic redirects to yumo.org
- HTTP → yumo.org HTTPS redirect
- HTTPS → yumo.org HTTPS redirect
- Both apex and www subdomain redirect

---

## Updating the Website

### Quick Deployment

Deploy all files to production:

```bash
cd /Users/ciline/Documents/development/projects/Lumie_APP
scp -i ~/.ssh/Lumie_Key.pem -r ./website/* ubuntu@54.193.153.37:/home/ubuntu/website/
```

**Note:** Changes are live immediately (no server restart needed in DEV mode)

### Deploy Specific Files

```bash
# HTML only
scp -i ~/.ssh/Lumie_Key.pem ./website/index.html ubuntu@54.193.153.37:/home/ubuntu/website/

# CSS only
scp -i ~/.ssh/Lumie_Key.pem ./website/styles.css ubuntu@54.193.153.37:/home/ubuntu/website/

# JavaScript only
scp -i ~/.ssh/Lumie_Key.pem ./website/script.js ubuntu@54.193.153.37:/home/ubuntu/website/

# Assets only
scp -i ~/.ssh/Lumie_Key.pem -r ./website/assets/* ubuntu@54.193.153.37:/home/ubuntu/website/assets/
```

### Verify Changes

1. Visit https://yumo.org
2. Hard refresh to bypass browser cache:
   - **Mac:** `Cmd + Shift + R`
   - **Windows/Linux:** `Ctrl + Shift + R`
3. Check that your changes appear

---

## Backend API Deployment

### API Server Information

**API Endpoint:** http://54.193.153.37:8000
**API Documentation:** http://54.193.153.37:8000/docs (Swagger UI)
**Health Check:** http://54.193.153.37:8000/api/v1/health

**Backend Location:**
- **Code Directory:** `/home/ubuntu/lumie_backend`
- **Virtual Environment:** `/home/ubuntu/lumie_backend/venv`
- **Service Config:** `/etc/systemd/system/lumie-api.service`
- **Environment File:** `/home/ubuntu/lumie_backend/.env`

**Tech Stack:**
- **Framework:** FastAPI 0.109.0
- **Server:** Uvicorn with 4 workers
- **Database:** MongoDB 8.0
- **Python:** 3.12
- **Authentication:** JWT with bcrypt

### Quick Backend Deployment

Deploy backend code to production:

```bash
cd /Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend
bash deploy.sh
```

**What the deploy script does:**
1. Creates tar archive (excludes venv, .git, __pycache__)
2. Uploads to server via SCP
3. Extracts files on server
4. Sets up Python virtual environment
5. Installs dependencies from requirements.txt
6. Checks MongoDB status

**After deployment, restart the service:**

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart lumie-api"
```

### One-Time Server Setup

**Initial server setup (already completed):**

```bash
cd /Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend
scp -i ~/.ssh/Lumie_Key.pem init-server.sh ubuntu@54.193.153.37:/home/ubuntu/lumie_backend/
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
cd /home/ubuntu/lumie_backend
bash init-server.sh
```

**What init-server.sh does:**
1. Installs system dependencies (Python 3, pip, venv)
2. Installs and configures MongoDB 8.0
3. Creates .env file with secure SECRET_KEY
4. Sets up systemd service (lumie-api.service)
5. Configures auto-start on boot

### Backend Service Management

```bash
# Check service status
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl status lumie-api"

# Start service
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl start lumie-api"

# Stop service
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl stop lumie-api"

# Restart service (after code changes)
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart lumie-api"

# View service logs (real-time)
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo journalctl -u lumie-api -f"

# View recent logs (last 50 lines)
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo journalctl -u lumie-api -n 50 --no-pager"
```

### MongoDB Management

```bash
# Check MongoDB status
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl status mongod"

# Start MongoDB
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl start mongod"

# Connect to MongoDB shell
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "mongosh"

# View databases
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "mongosh --eval 'show dbs'"
```

### Testing the API

```bash
# Health check
curl http://54.193.153.37:8000/api/v1/health

# Get activity types
curl http://54.193.153.37:8000/api/v1/activity-types

# View API documentation
# Visit: http://54.193.153.37:8000/docs
```

### Environment Variables

**Production environment file:** `/home/ubuntu/lumie_backend/.env`

```bash
# View current environment (sensitive info hidden)
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "cat /home/ubuntu/lumie_backend/.env"

# Edit environment variables
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "nano /home/ubuntu/lumie_backend/.env"

# After editing .env, restart service
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart lumie-api"
```

**Key environment variables:**
- `MONGODB_URL` - MongoDB connection string
- `MONGODB_DB_NAME` - Database name (lumie_production)
- `SECRET_KEY` - JWT signing key (auto-generated)
- `ACCESS_TOKEN_EXPIRE_MINUTES` - Token expiry (10080 = 7 days)
- `CORS_ORIGINS` - Allowed origins for API access

### Troubleshooting Backend Issues

**API not responding:**

```bash
# 1. Check service status
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl status lumie-api"

# 2. Check logs for errors
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo journalctl -u lumie-api -n 100 --no-pager"

# 3. Check if port 8000 is listening
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo lsof -i :8000"

# 4. Check MongoDB is running
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl status mongod"
```

**Port conflict (Address already in use):**

```bash
# Find process using port 8000
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo lsof -i :8000"

# Kill the process (replace PID)
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo kill -9 <PID>"

# Restart service
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart lumie-api"
```

**Service keeps restarting:**

```bash
# View detailed logs
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo journalctl -u lumie-api -n 200 --no-pager | grep -A 10 'ERROR'"

# Check Python errors
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "cd /home/ubuntu/lumie_backend && source venv/bin/activate && python -c 'import app.main'"
```

### API Endpoints

**Available endpoints:**

```
GET  /api/v1/health                  - Health check
GET  /api/v1/activity-types          - Get activity types
GET  /api/v1/activity/daily          - Daily activity summary
GET  /api/v1/activity/weekly         - Weekly activity summaries
POST /api/v1/activity                - Create manual activity
GET  /api/v1/ring/status             - Ring connection status
POST /api/v1/auth/signup             - User registration
POST /api/v1/auth/login              - User login
GET  /api/v1/profile                 - Get user profile
POST /api/v1/profile/teen            - Create teen profile
POST /api/v1/profile/parent          - Create parent profile
```

**Full API documentation:** http://54.193.153.37:8000/docs

---

## Server Management

### Connect to Server

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
```

### Nginx Commands

```bash
# Check Nginx status
sudo systemctl status nginx

# Restart Nginx (full restart)
sudo systemctl restart nginx

# Reload Nginx (graceful, no downtime)
sudo systemctl reload nginx

# Test Nginx configuration
sudo nginx -t

# View full Nginx configuration
sudo nginx -T
```

### View Logs

```bash
# View error log (last 50 lines)
sudo tail -50 /var/log/nginx/error.log

# View error log (real-time)
sudo tail -f /var/log/nginx/error.log

# View access log (last 100 lines)
sudo tail -100 /var/log/nginx/access.log

# View access log (real-time)
sudo tail -f /var/log/nginx/access.log
```

### View Nginx Configurations

```bash
# View yumo.org config
cat /etc/nginx/sites-available/yumo.org

# View yumo.life config
cat /etc/nginx/sites-available/yumo.life

# List enabled sites
ls -la /etc/nginx/sites-enabled/
```

### Check Website Files

```bash
# List website files
ls -lh /home/ubuntu/website/

# View file permissions
ls -la /home/ubuntu/website/

# Check assets folder
ls -lh /home/ubuntu/website/assets/
```

---

## SSL Certificate

### Certificate Details

- **Domains:** yumo.org, www.yumo.org, yumo.life, www.yumo.life
- **Type:** Let's Encrypt (bundled certificate)
- **Auto-Renewal:** ✅ Enabled
- **Certificate Path:** `/etc/letsencrypt/live/yumo-bundle/`

### Check Certificate Status

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 \
  "sudo certbot certificates"
```

### Manual Certificate Renewal

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 \
  "sudo certbot renew"
```

### Test Renewal (Dry Run)

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 \
  "sudo certbot renew --dry-run"
```

---

## Enabling Production Caching

**Current:** Caching is disabled (DEV mode) for quick development updates

**To enable caching for production:**

1. **Edit yumo.org config:**
   ```bash
   ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
   sudo nano /etc/nginx/sites-available/yumo.org
   ```

2. **Remove DEV cache headers:**
   ```nginx
   # Remove or comment out these lines:
   # add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0" always;
   # add_header Pragma "no-cache" always;
   # add_header Expires "0" always;
   ```

3. **Add production cache settings:**
   ```nginx
   # Add this location block for static assets:
   location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|mp4|webm)$ {
       expires 1y;
       add_header Cache-Control "public, immutable";
   }
   ```

4. **Reload Nginx:**
   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```

---

## Troubleshooting

### Website Not Loading

**Check Nginx status:**
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl status nginx"
```

**Check error logs:**
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo tail -50 /var/log/nginx/error.log"
```

**Test Nginx config:**
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo nginx -t"
```

### Changes Not Appearing

**Solution 1:** Hard refresh browser (Cmd+Shift+R or Ctrl+Shift+R)

**Solution 2:** Check file upload was successful
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "stat /home/ubuntu/website/index.html"
```

**Solution 3:** Verify file permissions
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "ls -la /home/ubuntu/website/"
```

### Domain Not Resolving

**Check DNS:**
```bash
# Check yumo.org
dig yumo.org +short

# Check yumo.life
dig yumo.life +short

# Both should return: 54.193.153.37
```

**Check globally:** https://dnschecker.org

### SSL Certificate Issues

**Check certificate expiry:**
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo certbot certificates"
```

**Force renewal:**
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo certbot renew --force-renewal"
```

---

## Testing URLs

### All Valid Access Methods

```bash
# Primary domain (preferred)
curl -I https://yumo.org

# WWW subdomain (redirects to apex)
curl -I https://www.yumo.org

# HTTP (redirects to HTTPS)
curl -I http://yumo.org

# Secondary domain (redirects to yumo.org)
curl -I https://yumo.life
curl -I https://www.yumo.life
curl -I http://yumo.life
```

### Expected Behavior

- ✅ https://yumo.org → **200 OK** (serves content)
- ✅ https://www.yumo.org → **301 redirect** → https://yumo.org
- ✅ http://yumo.org → **301 redirect** → https://yumo.org
- ✅ https://yumo.life → **301 redirect** → https://yumo.org
- ✅ https://www.yumo.life → **301 redirect** → https://yumo.org
- ✅ http://yumo.life → **301 redirect** → https://yumo.org

---

## Performance

**Optimization Features:**
- ✅ HTTP/2 enabled
- ✅ Gzip compression (~70% reduction)
- ⚠️ Caching disabled (DEV mode - enable for production)
- ✅ SSL/TLS configured
- ✅ Security headers enabled

**Load Times (DEV mode):**
- First Load: 1-2 seconds
- Subsequent Loads: 800ms-1.2s (no cache)
- With Cache (production): 200-500ms

**File Sizes:**
- HTML: 37 KB
- CSS: 27 KB
- JavaScript: 13 KB
- Videos: ~2-5 MB each

---

## Quick Reference Commands

```bash
# Deploy website
scp -i ~/.ssh/Lumie_Key.pem -r ./website/* ubuntu@54.193.153.37:/home/ubuntu/website/

# Connect to server
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37

# Restart Nginx
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart nginx"

# View error logs
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo tail -50 /var/log/nginx/error.log"

# Check SSL certificate
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo certbot certificates"

# Test Nginx config
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo nginx -t"
```

---

## Security Best Practices

1. **Keep server updated:**
   ```bash
   ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
   sudo apt update && sudo apt upgrade -y
   ```

2. **Monitor SSL certificate:**
   - Auto-renews every 90 days
   - Check status: `sudo certbot certificates`

3. **Review logs regularly:**
   ```bash
   sudo tail -100 /var/log/nginx/access.log
   sudo tail -100 /var/log/nginx/error.log
   ```

4. **Backup website files:**
   ```bash
   scp -i ~/.ssh/Lumie_Key.pem -r ubuntu@54.193.153.37:/home/ubuntu/website ./backup-$(date +%Y%m%d)
   ```

---

## Support

**Check Status:**
- Website: https://yumo.org
- SSL Test: https://www.ssllabs.com/ssltest/analyze.html?d=yumo.org
- DNS Checker: https://dnschecker.org

**Common Commands:**
- Check logs: `sudo tail -50 /var/log/nginx/error.log`
- Test config: `sudo nginx -t`
- Restart: `sudo systemctl restart nginx`

---

**Last Updated:** January 28, 2026

**Website Status:** 🟢 Live at https://yumo.org (yumo.life redirects here)
