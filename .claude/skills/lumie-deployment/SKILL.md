# Lumie Deployment Skill

## Description
Automate deployment of Lumie website and backend API to production server, including frontend website, FastAPI backend, MongoDB database management, and SSL certificate maintenance

## When to Use
- User requests deployment, release, or production updates
- Need to update production environment code
- Keywords: deploy, deployment, release, push to production, update website, restart service

## Server Information

### Basic Info
- **Server IP:** 54.193.153.37
- **Server OS:** Ubuntu 24.04
- **SSH Key:** `~/.ssh/Lumie_Key.pem`
- **User:** ubuntu

### Domain Configuration
- **Primary Domain:** yumo.org (HTTPS ✅)
- **Redirect Domain:** yumo.life → yumo.org
- **SSL Certificate:** Let's Encrypt (auto-renewal ✅)

### Service Status
- **Website:** 🟢 https://yumo.org
- **API:** 🟢 http://54.193.153.37:8000
- **Database:** 🟢 MongoDB 8.0
- **Web Server:** 🟢 Nginx 1.24.0

### DNS Configuration

#### yumo.org (Primary Domain)
Configure these A records on GoDaddy for yumo.org:

| Type | Name | Value | TTL |
|------|------|-------|-----|
| A | @ | 54.193.153.37 | 1800 |
| A | www | 54.193.153.37 | 1800 |

#### yumo.life (Redirect Domain)
Configure these A records on GoDaddy for yumo.life:

| Type | Name | Value | TTL |
|------|------|-------|-----|
| A | @ | 54.193.153.37 | 1800 |
| A | www | 54.193.153.37 | 1800 |

**Redirect Behavior:**
- http://yumo.org → https://yumo.org ✅
- http://www.yumo.org → https://yumo.org ✅
- https://www.yumo.org → https://yumo.org ✅
- http://yumo.life → https://yumo.org ✅
- https://yumo.life → https://yumo.org ✅
- http://www.yumo.life → https://yumo.org ✅
- https://www.yumo.life → https://yumo.org ✅

### Nginx Configuration

#### yumo.org Configuration
**File:** `/etc/nginx/sites-available/yumo.org`

**Features:**
- HTTP → HTTPS redirect
- www → apex redirect (www.yumo.org → yumo.org)
- Serves content from `/home/ubuntu/website`
- **DEV mode:** Caching disabled for quick updates
- Gzip compression enabled
- Security headers enabled

#### yumo.life Configuration
**File:** `/etc/nginx/sites-available/yumo.life`

**Features:**
- All traffic redirects to yumo.org
- HTTP → yumo.org HTTPS redirect
- HTTPS → yumo.org HTTPS redirect
- Both apex and www subdomain redirect

### SSL Certificate Details
- **Domains:** yumo.org, www.yumo.org, yumo.life, www.yumo.life
- **Type:** Let's Encrypt (bundled certificate)
- **Auto-Renewal:** ✅ Enabled
- **Certificate Path:** `/etc/letsencrypt/live/yumo-bundle/`

## Prerequisites

### Local Environment
- SSH key located at `~/.ssh/Lumie_Key.pem`
- Project directory: `/Users/ciline/Documents/development/projects/Lumie_APP`

### Server Environment
- **Website Directory:** `/home/ubuntu/website`
- **Backend Directory:** `/home/ubuntu/lumie_backend`
- **Python Virtual Env:** `/home/ubuntu/lumie_backend/venv`
- **Nginx Config:** `/etc/nginx/sites-available/yumo.org`
- **systemd Service:** `lumie-api.service`

## Instructions

### 🌐 Website Deployment (Frontend)

#### 1. Deploy All Website Files
```bash
cd /Users/ciline/Documents/development/projects/Lumie_APP
scp -i ~/.ssh/Lumie_Key.pem -r ./website/* ubuntu@54.193.153.37:/home/ubuntu/website/
```

**Note:** Changes take effect immediately in DEV mode, no Nginx restart needed

#### 2. Deploy Specific Files
```bash
# Deploy HTML only
scp -i ~/.ssh/Lumie_Key.pem ./website/index.html ubuntu@54.193.153.37:/home/ubuntu/website/

# Deploy CSS only
scp -i ~/.ssh/Lumie_Key.pem ./website/styles.css ubuntu@54.193.153.37:/home/ubuntu/website/

# Deploy JavaScript only
scp -i ~/.ssh/Lumie_Key.pem ./website/script.js ubuntu@54.193.153.37:/home/ubuntu/website/

# Deploy assets
scp -i ~/.ssh/Lumie_Key.pem -r ./website/assets/* ubuntu@54.193.153.37:/home/ubuntu/website/assets/
```

#### 3. Verify Deployment
1. Visit https://yumo.org
2. Hard refresh browser cache:
   - **Mac:** `Cmd + Shift + R`
   - **Windows/Linux:** `Ctrl + Shift + R`
3. Check if changes are applied

### 🚀 Backend API Deployment

#### 1. Quick Deploy (Recommended)
```bash
cd /Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend
bash deploy.sh
```

**deploy.sh performs:**
- Create tar archive (excludes venv, .git, __pycache__)
- Upload via SCP to server
- Extract files on server
- Set up Python virtual environment
- Install dependencies (requirements.txt)
- Check MongoDB status

#### 2. Restart API Service
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart lumie-api"
```

#### 3. Verify API Deployment
```bash
# Health check
curl http://54.193.153.37:8000/api/v1/health

# View API documentation
# Browser: http://54.193.153.37:8000/docs
```

### 📊 Service Management

#### API Service (lumie-api.service)
```bash
# Check status
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl status lumie-api"

# Start service
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl start lumie-api"

# Stop service
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl stop lumie-api"

# Restart service (after code updates)
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart lumie-api"

# View real-time logs
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo journalctl -u lumie-api -f"

# View last 50 log lines
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo journalctl -u lumie-api -n 50 --no-pager"
```

#### MongoDB Database
```bash
# Check status
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl status mongod"

# Start MongoDB
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl start mongod"

# Connect to MongoDB shell
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "mongosh"

# View database list
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "mongosh --eval 'show dbs'"
```

#### Nginx Web Server
```bash
# Check status
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl status nginx"

# Restart Nginx (full restart)
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart nginx"

# Reload config (graceful restart, no downtime)
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl reload nginx"

# Test Nginx config
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo nginx -t"

# View full config
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo nginx -T"
```

### 🔐 SSL Certificate Management

#### Check Certificate Status
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo certbot certificates"
```

#### Manual Certificate Renewal
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo certbot renew"
```

#### Test Renewal (Dry Run)
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo certbot renew --dry-run"
```

## Examples

### Example 1: Complete Deployment Flow (Website + API)
```bash
# 1. Deploy frontend website
cd /Users/ciline/Documents/development/projects/Lumie_APP
scp -i ~/.ssh/Lumie_Key.pem -r ./website/* ubuntu@54.193.153.37:/home/ubuntu/website/

# 2. Deploy backend API
cd /Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend
bash deploy.sh

# 3. Restart API service
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart lumie-api"

# 4. Verify deployment
curl https://yumo.org
curl http://54.193.153.37:8000/api/v1/health

echo "✅ Deployment complete!"
```

### Example 2: Frontend Only Update
```bash
cd /Users/ciline/Documents/development/projects/Lumie_APP
scp -i ~/.ssh/Lumie_Key.pem -r ./website/* ubuntu@54.193.153.37:/home/ubuntu/website/

# Immediately visit https://yumo.org to check changes (hard refresh browser)
```

### Example 3: Backend Only Update
```bash
cd /Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend
bash deploy.sh
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart lumie-api"

# Check health status
curl http://54.193.153.37:8000/api/v1/health
```

### Example 4: Quick Check All Service Status
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 << 'EOF'
echo "=== Nginx Status ==="
sudo systemctl status nginx --no-pager | head -3

echo -e "\n=== API Service Status ==="
sudo systemctl status lumie-api --no-pager | head -3

echo -e "\n=== MongoDB Status ==="
sudo systemctl status mongod --no-pager | head -3

echo -e "\n=== SSL Certificate Status ==="
sudo certbot certificates 2>/dev/null | grep "Expiry Date"

echo -e "\n=== Disk Usage ==="
df -h / | tail -1
EOF
```

## Infrastructure Configuration

### Enabling Production Caching

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

### Testing Deployment

#### Test All URLs
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

#### Expected Behavior
- ✅ https://yumo.org → **200 OK** (serves content)
- ✅ https://www.yumo.org → **301 redirect** → https://yumo.org
- ✅ http://yumo.org → **301 redirect** → https://yumo.org
- ✅ https://yumo.life → **301 redirect** → https://yumo.org
- ✅ https://www.yumo.life → **301 redirect** → https://yumo.org
- ✅ http://yumo.life → **301 redirect** → https://yumo.org

#### DNS Verification
```bash
# Check yumo.org
dig yumo.org +short

# Check yumo.life
dig yumo.life +short

# Both should return: 54.193.153.37
```

**Check globally:** https://dnschecker.org

### Performance Metrics

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

## Error Handling

### Error 1: Website Not Accessible
**Diagnostic Steps:**
```bash
# 1. Check Nginx status
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl status nginx"

# 2. View error logs
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo tail -50 /var/log/nginx/error.log"

# 3. Test Nginx config
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo nginx -t"
```

**Solutions:**
- Config error: Fix and run `sudo nginx -t && sudo systemctl reload nginx`
- Service not started: `sudo systemctl start nginx`

### Error 2: API Not Responding
**Diagnostic Steps:**
```bash
# 1. Check service status
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl status lumie-api"

# 2. View error logs
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo journalctl -u lumie-api -n 100 --no-pager"

# 3. Check port usage
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo lsof -i :8000"

# 4. Check MongoDB
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl status mongod"
```

**Solutions:**
- Service crashed: Check logs for errors, fix, then restart
- Port conflict: `sudo kill -9 <PID>` then restart service
- MongoDB not running: `sudo systemctl start mongod`

### Error 3: Address Already in Use
```bash
# 1. Find process using port 8000
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo lsof -i :8000"

# 2. Check for duplicate services (IMPORTANT!)
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl list-units --type=service | grep lumie"

# 3. If lumie-backend.service exists, disable it (it's a duplicate)
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl stop lumie-backend.service"
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl disable lumie-backend.service"

# 4. Kill rogue processes (if needed, replace <PID>)
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo kill -9 <PID>"

# 5. Restart the correct service
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart lumie-api"
```

**Note:** Only `lumie-api.service` should be running. If you find `lumie-backend.service`, it's a duplicate that must be stopped and disabled.

### Error 4: Changes Not Applied
**Solution 1:** Hard refresh browser (Cmd+Shift+R or Ctrl+Shift+R)

**Solution 2:** Check file upload succeeded
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "stat /home/ubuntu/website/index.html"
```

**Solution 3:** Verify file permissions
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "ls -la /home/ubuntu/website/"
```

### Error 5: SSL Certificate Issues
```bash
# Check certificate expiry
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo certbot certificates"

# Force renewal
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo certbot renew --force-renewal"

# Reload Nginx
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl reload nginx"
```

## Safety Checks

### ⚠️ Before Production Deployment
1. **Confirm code is tested:** Ensure all tests pass
2. **Check git status:** Ensure all changes are committed
3. **Backup database:** Backup MongoDB before major updates
4. **Notify users:** Inform users if there will be downtime

### ✅ Post-Deployment Verification
```bash
# 1. Website health check
curl -I https://yumo.org

# 2. API health check
curl http://54.193.153.37:8000/api/v1/health

# 3. Check service logs
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo journalctl -u lumie-api -n 20 --no-pager"

# 4. Monitor service status
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl status lumie-api nginx mongod"
```

### 🔄 Rollback Plan
If deployment has issues:

**Frontend Rollback:**
```bash
# Restore from backup
scp -i ~/.ssh/Lumie_Key.pem -r ./backup-20260207/* ubuntu@54.193.153.37:/home/ubuntu/website/
```

**Backend Rollback:**
```bash
# Restore to previous version
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "cd /home/ubuntu/lumie_backend && git checkout <previous-commit>"
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart lumie-api"
```

### Security Best Practices

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
   sudo journalctl -u lumie-api -n 100 --no-pager
   ```

4. **Backup website and database:**
   ```bash
   # Backup website files
   scp -i ~/.ssh/Lumie_Key.pem -r ubuntu@54.193.153.37:/home/ubuntu/website ./backup-$(date +%Y%m%d)

   # Backup MongoDB (on server)
   ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "mongodump --db lumie_db --out /tmp/mongo-backup-$(date +%Y%m%d)"
   ```

5. **Security Testing Tools:**
   - **SSL Test:** https://www.ssllabs.com/ssltest/analyze.html?d=yumo.org
   - **DNS Checker:** https://dnschecker.org
   - **Security Headers:** https://securityheaders.com/?q=yumo.org

## Environment Management

### Environment Variables Configuration
**Production environment file:** `/home/ubuntu/lumie_backend/.env`

```bash
# View environment variables (sensitive info hidden)
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "cat /home/ubuntu/lumie_backend/.env"

# Edit environment variables
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "nano /home/ubuntu/lumie_backend/.env"

# Restart service after changes
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart lumie-api"
```

**Key Environment Variables:**
- `MONGODB_URL` - MongoDB connection string
- `MONGODB_DB_NAME` - Database name (lumie_db)
- `SECRET_KEY` - JWT signing key (auto-generated)
- `ACCESS_TOKEN_EXPIRE_MINUTES` - Token expiry (10080 = 7 days)
- `CORS_ORIGINS` - Allowed API origins

## API Endpoints

### Available Endpoints
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

**Full API Documentation:** http://54.193.153.37:8000/docs

## Quick Reference

### Common Commands Cheat Sheet
```bash
# Deploy website
scp -i ~/.ssh/Lumie_Key.pem -r ./website/* ubuntu@54.193.153.37:/home/ubuntu/website/

# Deploy API
cd lumie_backend && bash deploy.sh

# Restart API
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart lumie-api"

# Restart Nginx
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart nginx"

# View API logs
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo journalctl -u lumie-api -f"

# View Nginx error logs
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo tail -50 /var/log/nginx/error.log"

# Health check
curl https://yumo.org && curl http://54.193.153.37:8000/api/v1/health
```

### Connect to Server
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
```

---

**Status:** 🟢 All Services Running
**Website:** https://yumo.org
**API:** http://54.193.153.37:8000
**Database:** lumie_db (MongoDB 8.0)
**Last Updated:** 2026-02-10
**Server:** 54.193.153.37 (Ubuntu 24.04)
