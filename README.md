# Lumie Health - Teen-First Health Platform

**Live Website:** https://yumo.life

A compassionate health platform designed specifically for teens (ages 13-21) living with chronic conditions. Lumie combines a wearable ring with an intuitive app to help teens understand their body's trends, balance activity with recovery, and maintain control over their health journey—without labels, pressure, or social comparison.

---

## 🎯 Mission

Growing up with a chronic condition shouldn't mean growing up with shame, fear, or constant comparison. Lumie gives teens a sense of understanding and control through:

- **Teen-First Design** - Built with and for teens, not adapted from adult tools
- **Non-Clinical Language** - Health insights without medical anxiety
- **No Shame** - Your health journey is yours—no judgment, no pressure

---

## 🌟 Core Features

### The Lumie Experience: Ring + App

**Get Started Without Hardware**
- Create your profile and begin tracking habits, medications, and wellness
- No ring required to start using the app

**Pair When Ready**
- Connect your Lumie ring to unlock deeper biometric insights
- Sleep, activity, stress, and fatigue monitoring

**Your Baseline, Your Progress**
- All metrics compare against your own trends over time
- Never compared against other people

### Health Tracking Features

| Feature | Description |
|---------|-------------|
| **Activity Tracking** | Including 6-Minute Walk Test (6MWT) support |
| **Sleep Insights** | Understand rest patterns and energy levels |
| **Fatigue Index** | Track tiredness and identify patterns |
| **Stress Signals** | Recognize body signals of stress |
| **Habit Tracker** | Build routines that support health goals |
| **Med Reminders** | Never miss a dose with gentle notifications |
| **Teen-Friendly Education** | Medical concepts in plain language |
| **Personal Advisor** | Contextual tips based on your data |
| **Peer Chat (Optional)** | Connect safely with strict boundaries |

### Privacy & Safety (Teen-Focused)

- ✅ No calorie burn tracking
- ✅ No MET values or performance ranking
- ✅ All comparisons are self-referenced only
- ✅ Manual entries clearly labeled as "Estimated"
- ✅ 6MWT results are informational, not diagnostic
- ✅ No public leaderboards or social comparison
- ✅ Sharing is off by default
- ✅ Teens can revoke family access instantly

---

## 🌐 Marketing Website

### Production Website

**URL:** https://yumo.life
**Status:** 🟢 Live and fully operational
**Last Deployed:** January 26, 2026

### Design Features

**Scroll-Driven Storytelling**
- Hero visual with video background (buildings2.mp4)
- Multiple sections with smooth scroll animations
- Parallax effects for engaging experience
- Video animation in "Trends over time" section

**Color Palette**
- Primary: Soft golden yellow (#F4C14A)
- Secondary: Soft teal (#9BC4C7)
- Backgrounds: Warm cream and beige tones
- Inspired by custom illustrations

**15 Content Sections:**
1. Hero - "Health that grows with you"
2. Introduction - Quick overview
3. Product - Ring + App experience
4. Features - 9 core features
5. For Teens - Teen-focused benefits
6. For Families - Family system
7. Safety & Privacy - Security features
8. Science & Approach - Data methodology
9. Conditions - Condition groups
10. Community - Peer support
11. Pricing - 3 pricing tiers
12. FAQ - Common questions
13. About - Mission and values
14. Partners - B2B2C collaboration
15. Resources - Educational guides
16. Contact - Support and demo requests

### Technical Stack

**Frontend:**
- HTML5, CSS3, Vanilla JavaScript
- Responsive design (mobile-first)
- Scroll-driven animations (Intersection Observer)
- Video background optimization

**Backend Infrastructure:**
- Nginx 1.24.0 (Ubuntu 24.04)
- SSL/TLS certificate (Let's Encrypt)
- HTTPS with automatic HTTP redirect
- HTTP/2, Gzip compression
- AWS EC2 (US West 1)

**Deployment Status:**

| Component | Status |
|-----------|--------|
| Website | 🟢 Live at https://yumo.life |
| SSL | 🟢 Active until April 26, 2026 |
| DNS | 🟢 Configured on GoDaddy |
| Auto-Renewal | 🟢 Enabled |

---

## 📱 Flutter App Demo

A Flutter + Python demo application for the Lumie Activity feature, designed for teens aged 13-21 with chronic health conditions.

### Activity App Features

**Activity Tracking**
- **Activity Time**: Daily aggregate of physical movement duration
- **Activity Intensity**: Teen-safe categorical scale (Low, Moderate, High)
- **Adaptive Goals**: Personalized daily targets based on sleep and recovery
- **Manual Entry**: Fallback activity logging with ring detection support
- **Six-Minute Walk Test**: Self-referenced functional fitness check-in

**Design**
- Light/Lemon Yellow theme with gradient accents
- Modern, accessible UI designed for teens
- Ring status indicators and connection management

### App Screenshots

The app features:
1. **Dashboard**: Activity ring, daily summary, adaptive goals
2. **History**: Week view with day-by-day breakdown
3. **Manual Entry**: Activity type selection, time picker, intensity
4. **6MWT**: Instructions, live timer, heart rate, results

---

## 📁 Project Structure

```
Lumie_APP/
├── website/                          # Marketing Website (LIVE)
│   ├── index.html                   # Main HTML (37 KB)
│   ├── styles.css                   # Stylesheet (27 KB)
│   ├── script.js                    # JavaScript (13 KB)
│   └── assets/                      # Media files
│       ├── buildings2.mp4           # Hero video
│       ├── buildings2.png           # Background reference
│       ├── animation_placement.mp4  # Science section video
│       ├── illustration_placement.png
│       └── illustration_placement2.png
│
├── lumie_activity_app/              # Flutter App Demo
│   └── lib/
│       ├── core/
│       │   ├── theme/               # Color palette & theme
│       │   ├── constants/           # API constants
│       │   └── utils/               # API service
│       ├── features/
│       │   ├── dashboard/           # Home screen
│       │   ├── activity/            # Activity history
│       │   ├── manual_entry/        # Manual logging
│       │   └── walk_test/           # 6-Minute Walk Test
│       └── shared/
│           ├── models/              # Data models
│           └── widgets/             # Reusable components
│
├── lumie_backend/                   # Python Backend
│   └── app/
│       ├── api/                     # FastAPI routes
│       ├── models/                  # Pydantic models
│       └── services/                # Business logic
│
├── DEPLOYMENT_README.md             # Complete deployment guide
├── DEPLOYMENT_GUIDE.md              # Quick setup reference
├── DEPLOYMENT_STATUS.md             # Current status dashboard
├── VIDEO_GENERATION_README.md       # Video generation guide
└── README.md                        # This file

Server Deployment:
/var/www/yumo.life/                  # Production website
/etc/nginx/sites-available/yumo.life # Nginx config
/etc/letsencrypt/live/yumo.life/     # SSL certificates
```

---

## 🚀 Getting Started

### Website Development

**Local Preview:**
```bash
cd website
python3 -m http.server 8000
# Visit http://localhost:8000
```

**Deploy to Production:**
```bash
# Deploy all files
scp -i ~/.ssh/Lumie_Key.pem -r ./website/* ubuntu@54.193.153.37:/var/www/yumo.life/

# Deploy specific files
scp -i ~/.ssh/Lumie_Key.pem ./website/index.html ubuntu@54.193.153.37:/var/www/yumo.life/
```

**Verify Changes:**
1. Visit https://yumo.life
2. Hard refresh: `Cmd + Shift + R` (Mac) or `Ctrl + Shift + R` (Windows/Linux)

### App Development

**Backend (Python):**
```bash
cd lumie_backend

# Setup
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt

# Run server
python run.py
# API available at http://localhost:8000
```

**Frontend (Flutter):**
```bash
cd lumie_activity_app

# Setup
flutter pub get

# Run on device
flutter run -d ios      # iOS Simulator
flutter run -d android  # Android Emulator
flutter run -d chrome   # Web Browser
```

---

## 🔧 API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/activity-types` | GET | Get predefined activity types |
| `/api/v1/activity/daily` | GET | Get daily activity summary |
| `/api/v1/activity/weekly` | GET | Get 7-day activity summaries |
| `/api/v1/activity/goal` | GET | Get adaptive goal for a day |
| `/api/v1/activity` | POST | Create manual activity entry |
| `/api/v1/ring/status` | GET | Get Lumie Ring status |
| `/api/v1/ring/detected` | GET | Get ring-detected activities |
| `/api/v1/walk-test/history` | GET | Get walk test history |
| `/api/v1/walk-test` | POST | Save walk test result |
| `/api/v1/walk-test/best` | GET | Get best walk test result |

**API Documentation:**
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

---

## 🎨 Design System

### Website Colors

```css
/* Primary Colors */
--color-soft-yellow: #F4C14A;  /* Primary CTA, accents */
--color-golden: #E6A73C;       /* Hover states */
--color-soft-teal: #9BC4C7;    /* Secondary, features */

/* Backgrounds */
--color-warm-white: #FAF8F3;   /* Page background */
--color-cream: #F5F1E8;        /* Section backgrounds */
--color-beige: #E8E3D8;        /* Alternate sections */

/* Text */
--color-dark-text: #2C2C2C;    /* Headings, body */
--color-medium-text: #5A5A5A;  /* Secondary text */
--color-light-text: #8A8A8A;   /* Muted text */
```

### Typography

- **Fonts**: System fonts (SF Pro Display, Segoe UI, Roboto)
- **Hero Title**: 3rem - 6rem (responsive)
- **Section Titles**: 2.5rem - 4rem
- **Body Text**: 1rem - 1.25rem

### Responsive Breakpoints

- Mobile: 320px - 768px
- Tablet: 768px - 1024px
- Desktop: 1024px+

---

## 🔐 Server Management

### SSH Access

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
```

### Common Commands

```bash
# Nginx
sudo systemctl status nginx    # Check status
sudo systemctl restart nginx   # Restart
sudo systemctl reload nginx    # Reload (no downtime)
sudo nginx -t                  # Test config

# Logs
sudo tail -50 /var/log/nginx/error.log   # Error logs
sudo tail -100 /var/log/nginx/access.log # Access logs

# SSL Certificate
sudo certbot certificates      # Check status
sudo certbot renew            # Manual renewal (auto-renews)
```

---

## 📊 Performance

### Website Performance

**Optimization Features:**
- ✅ Gzip compression (~70% reduction)
- ✅ Browser caching (1 year for static assets)
- ✅ HTTP/2 multiplexing
- ✅ Video optimization
- ✅ Lazy loading

**Load Times:**
- First Load: 1-2 seconds
- Cached Load: 200-500ms
- Video Playback: Instant (cached)

**File Sizes:**
- HTML: 37 KB
- CSS: 27 KB
- JavaScript: 13 KB
- Videos: ~2-5 MB each

---

## 🧪 Testing

### Website Testing

**Browsers:**
- ✅ Chrome (desktop & mobile)
- ✅ Safari (desktop & mobile)
- ✅ Firefox (desktop)
- ✅ Edge (desktop)

**Test URLs:**
- https://yumo.life
- https://www.yumo.life
- http://yumo.life (should redirect to HTTPS)

**Tools:**
- SSL Labs: https://www.ssllabs.com/ssltest/analyze.html?d=yumo.life
- PageSpeed: https://pagespeed.web.dev/
- DNS Checker: https://dnschecker.org

---

## 💰 Pricing

### App Only - $9.99/month
- Habit tracking, med reminders, education, advisor

### Ring + App - $299 (ring) + $14.99/month
- All App features + sleep, activity, stress, fatigue, 6MWT

### Family Plan - $39.99/month
- Up to 4 members, all features, privacy controls

**Trial:** 14-day free trial
**Return:** 30-day on ring
**Requirement:** Parental consent for users under 18

---

## 👥 For Different Users

### For Teens

- Less fear, more understanding
- No scoring, no comparison
- You decide what to share (off by default)
- No public profile, no social pressure

### For Parents & Families

- See only what teens choose to share
- Category-level controls
- Teens can revoke access instantly
- Focus on progress together

---

## 🔒 Privacy & Security

**Privacy-by-Default:**
- Your data is private (not sold, rented, or shared)
- Sharing requires explicit consent
- No medical labels displayed
- Not a medical device

**Teen Protection:**
- Strict chat boundaries (monitored, filtered)
- Photo sharing limits (medical images blocked)
- Age verification (COPPA compliant, 13+)

---

## 📈 Roadmap

### Completed ✅
- [x] Website design and development
- [x] Scroll-driven animations
- [x] AWS deployment with SSL
- [x] DNS configuration
- [x] Activity app demo (Flutter + Python)
- [x] 6-Minute Walk Test feature
- [x] Ring integration mockup

### In Progress 🚧
- [ ] Production app development
- [ ] Backend API expansion
- [ ] Analytics integration

### Planned 📋
- [ ] Sleep tracking feature
- [ ] Habit tracker module
- [ ] Med reminder system
- [ ] Family sharing features
- [ ] Peer chat (with safety controls)

---

## 📝 Documentation

**Website Deployment:**
- `DEPLOYMENT_README.md` - Complete deployment guide
- `DEPLOYMENT_GUIDE.md` - Quick setup reference
- `DEPLOYMENT_STATUS.md` - Current status dashboard

**Development:**
- `VIDEO_GENERATION_README.md` - Video generation guide
- `README.md` - This file (project overview)

---

## 🤝 Contributing

This is a private project for Yumo.org. For internal team members:

1. Test changes locally first
2. Document major changes
3. Deploy during low-traffic periods
4. Monitor logs after deployment
5. Keep documentation updated

---

## 📞 Support

**Website Issues:**
- Check server logs: `sudo tail -50 /var/log/nginx/error.log`
- Test Nginx: `sudo nginx -t`
- Restart: `sudo systemctl restart nginx`

**SSL Certificate:**
- Auto-renewal enabled (twice daily checks)
- Notifications: ciline@gmail.com
- Manual renewal: `sudo certbot renew`

**App Development:**
- Backend API docs: http://localhost:8000/docs
- Flutter docs: https://flutter.dev/docs

---

## 📚 Tech Stack

### Website
- HTML5, CSS3, Vanilla JavaScript
- Nginx 1.24.0 (Ubuntu 24.04)
- Let's Encrypt SSL
- AWS EC2

### App (Demo)
- **Frontend**: Flutter 3.x, Dart 3.x, Material Design 3
- **Backend**: Python 3.11+, FastAPI, Pydantic v2, Uvicorn

---

## 📄 License

Proprietary - © 2026 Yumo.org. All rights reserved.

---

## 🌟 Status

**Website:** 🟢 Live at https://yumo.life
**SSL:** 🟢 Active (expires April 26, 2026)
**App Demo:** 🟢 Functional (local development)

**Last Updated:** January 26, 2026

---

**Health that grows with you. Not labels. Not pressure.**

*Teen-first health, built for chronic conditions.*
