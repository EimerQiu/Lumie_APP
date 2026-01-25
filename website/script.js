// ================================
// SCROLL REVEAL ANIMATIONS
// ================================
const observerOptions = {
    threshold: 0.15,
    rootMargin: '0px 0px -50px 0px'
};

const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.classList.add('revealed');
        }
    });
}, observerOptions);

// Observe all elements with scroll-reveal class
document.addEventListener('DOMContentLoaded', () => {
    const revealElements = document.querySelectorAll('.scroll-reveal');
    revealElements.forEach(el => observer.observe(el));
});

// ================================
// NAVIGATION
// ================================
const mainNav = document.querySelector('.main-nav');
const mobileMenuToggle = document.querySelector('.mobile-menu-toggle');
const navLinks = document.querySelector('.nav-links');
let lastScrollY = window.scrollY;
let ticking = false;

// Hide/show navigation on scroll
function updateNav() {
    const currentScrollY = window.scrollY;

    if (currentScrollY > 100) {
        if (currentScrollY > lastScrollY) {
            // Scrolling down
            mainNav.classList.add('hidden');
        } else {
            // Scrolling up
            mainNav.classList.remove('hidden');
        }
    } else {
        mainNav.classList.remove('hidden');
    }

    lastScrollY = currentScrollY;
    ticking = false;
}

window.addEventListener('scroll', () => {
    if (!ticking) {
        window.requestAnimationFrame(updateNav);
        ticking = true;
    }
});

// Mobile menu toggle
if (mobileMenuToggle) {
    mobileMenuToggle.addEventListener('click', () => {
        navLinks.classList.toggle('active');
        mobileMenuToggle.classList.toggle('active');
    });
}

// Smooth scroll for navigation links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));

        if (target) {
            const offsetTop = target.offsetTop - 80; // Account for fixed nav
            window.scrollTo({
                top: offsetTop,
                behavior: 'smooth'
            });

            // Close mobile menu if open
            if (navLinks.classList.contains('active')) {
                navLinks.classList.remove('active');
                mobileMenuToggle.classList.remove('active');
            }
        }
    });
});

// ================================
// HERO VIDEO OPTIMIZATION
// ================================
const heroVideo = document.querySelector('.hero-video');
const bgVideos = document.querySelectorAll('.bg-video');

// Pause videos when not in viewport to save resources
const videoObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        const video = entry.target;
        if (entry.isIntersecting) {
            video.play().catch(e => console.log('Video play failed:', e));
        } else {
            video.pause();
        }
    });
}, { threshold: 0.25 });

if (heroVideo) videoObserver.observe(heroVideo);
bgVideos.forEach(video => videoObserver.observe(video));

// ================================
// PARALLAX EFFECTS
// ================================
let scrollPosition = 0;

function parallaxEffect() {
    scrollPosition = window.pageYOffset;

    // Hero parallax
    const heroContent = document.querySelector('.hero-content');
    if (heroContent && scrollPosition < window.innerHeight) {
        const translateY = scrollPosition * 0.5;
        heroContent.style.transform = `translateY(${translateY}px)`;
        heroContent.style.opacity = 1 - (scrollPosition / window.innerHeight);
    }

    // Video parallax
    if (heroVideo && scrollPosition < window.innerHeight) {
        const scale = 1 + (scrollPosition / window.innerHeight) * 0.2;
        heroVideo.style.transform = `scale(${scale})`;
    }
}

let parallaxTicking = false;

window.addEventListener('scroll', () => {
    if (!parallaxTicking) {
        window.requestAnimationFrame(() => {
            parallaxEffect();
            parallaxTicking = false;
        });
        parallaxTicking = true;
    }
});

// ================================
// SCROLL INDICATOR
// ================================
const scrollIndicator = document.querySelector('.scroll-indicator');

if (scrollIndicator) {
    window.addEventListener('scroll', () => {
        if (window.scrollY > 300) {
            scrollIndicator.style.opacity = '0';
            scrollIndicator.style.pointerEvents = 'none';
        } else {
            scrollIndicator.style.opacity = '1';
            scrollIndicator.style.pointerEvents = 'auto';
        }
    });

    scrollIndicator.addEventListener('click', () => {
        const introSection = document.querySelector('#introduction');
        if (introSection) {
            introSection.scrollIntoView({ behavior: 'smooth' });
        }
    });
}

// ================================
// DYNAMIC CARD ANIMATIONS
// ================================
const cards = document.querySelectorAll('.feature-card, .safety-card, .pricing-card, .faq-item, .resource-card');

cards.forEach(card => {
    card.addEventListener('mouseenter', function() {
        this.style.transition = 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)';
    });

    card.addEventListener('mouseleave', function() {
        this.style.transition = 'all 0.4s cubic-bezier(0.4, 0, 0.2, 1)';
    });
});

// ================================
// FORM HANDLING
// ================================
const contactForm = document.querySelector('.contact-form');

if (contactForm) {
    contactForm.addEventListener('submit', async (e) => {
        e.preventDefault();

        const formData = new FormData(contactForm);
        const submitButton = contactForm.querySelector('button[type="submit"]');
        const originalText = submitButton.textContent;

        // Disable button and show loading state
        submitButton.disabled = true;
        submitButton.textContent = 'Sending...';

        // Simulate form submission (replace with actual API call)
        setTimeout(() => {
            submitButton.textContent = 'Sent! ✓';
            submitButton.style.backgroundColor = 'var(--color-secondary)';

            // Reset form
            contactForm.reset();

            // Reset button after 3 seconds
            setTimeout(() => {
                submitButton.disabled = false;
                submitButton.textContent = originalText;
                submitButton.style.backgroundColor = '';
            }, 3000);
        }, 1500);

        // In production, replace the above with:
        /*
        try {
            const response = await fetch('/api/contact', {
                method: 'POST',
                body: formData
            });

            if (response.ok) {
                submitButton.textContent = 'Sent! ✓';
                contactForm.reset();
            } else {
                throw new Error('Failed to send');
            }
        } catch (error) {
            submitButton.textContent = 'Error - Try Again';
            submitButton.style.backgroundColor = '#e74c3c';
        } finally {
            setTimeout(() => {
                submitButton.disabled = false;
                submitButton.textContent = originalText;
                submitButton.style.backgroundColor = '';
            }, 3000);
        }
        */
    });
}

// ================================
// ACTIVE SECTION HIGHLIGHTING
// ================================
const sections = document.querySelectorAll('section[id]');
const navLinksArray = document.querySelectorAll('.nav-links a');

function highlightNavigation() {
    const scrollY = window.pageYOffset;

    sections.forEach(section => {
        const sectionHeight = section.offsetHeight;
        const sectionTop = section.offsetTop - 100;
        const sectionId = section.getAttribute('id');

        if (scrollY > sectionTop && scrollY <= sectionTop + sectionHeight) {
            navLinksArray.forEach(link => {
                link.classList.remove('active');
                if (link.getAttribute('href') === `#${sectionId}`) {
                    link.classList.add('active');
                }
            });
        }
    });
}

window.addEventListener('scroll', highlightNavigation);

// ================================
// PERFORMANCE OPTIMIZATIONS
// ================================

// Lazy load images
if ('loading' in HTMLImageElement.prototype) {
    const images = document.querySelectorAll('img[loading="lazy"]');
    images.forEach(img => {
        img.src = img.dataset.src;
    });
} else {
    // Fallback for browsers that don't support lazy loading
    const script = document.createElement('script');
    script.src = 'https://cdnjs.cloudflare.com/ajax/libs/lazysizes/5.3.2/lazysizes.min.js';
    document.body.appendChild(script);
}

// Reduce motion for users who prefer it
const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

if (prefersReducedMotion.matches) {
    // Disable parallax and heavy animations
    parallaxEffect = () => {}; // Override parallax function

    // Remove animation delays
    document.querySelectorAll('.scroll-reveal').forEach(el => {
        el.classList.add('revealed');
    });
}

// ================================
// PRICING CARD INTERACTIONS
// ================================
const pricingCards = document.querySelectorAll('.pricing-card');

pricingCards.forEach(card => {
    const button = card.querySelector('.btn');

    if (button) {
        button.addEventListener('click', (e) => {
            e.preventDefault();

            // Get the plan type
            const planType = card.querySelector('h3').textContent;

            // In production, this would redirect to a checkout page or open a modal
            console.log(`Selected plan: ${planType}`);

            // Show a simple alert for demo purposes
            alert(`You selected the ${planType} plan. In production, this would proceed to checkout.`);
        });
    }
});

// ================================
// FAQ ACCORDION (Optional Enhancement)
// ================================
const faqItems = document.querySelectorAll('.faq-item');

faqItems.forEach(item => {
    item.style.cursor = 'pointer';

    item.addEventListener('click', () => {
        // Toggle expanded state
        item.classList.toggle('expanded');

        // Optional: Add animation for answer reveal
        const answer = item.querySelector('p');
        if (item.classList.contains('expanded')) {
            answer.style.maxHeight = answer.scrollHeight + 'px';
        } else {
            answer.style.maxHeight = null;
        }
    });
});

// ================================
// PROGRESSIVE ENHANCEMENT
// ================================

// Add smooth reveal for images as they load
document.querySelectorAll('img').forEach(img => {
    img.style.opacity = '0';
    img.style.transition = 'opacity 0.6s ease';

    if (img.complete) {
        img.style.opacity = '1';
    } else {
        img.addEventListener('load', () => {
            img.style.opacity = '1';
        });
    }
});

// ================================
// RESIZE HANDLER
// ================================
let resizeTimer;

window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
        // Recalculate positions after resize
        highlightNavigation();

        // Reset parallax on mobile
        if (window.innerWidth < 768) {
            const heroContent = document.querySelector('.hero-content');
            if (heroContent) {
                heroContent.style.transform = '';
                heroContent.style.opacity = '1';
            }
        }
    }, 250);
});

// ================================
// EASTER EGG: KONAMI CODE
// ================================
let konamiCode = [];
const konamiSequence = ['ArrowUp', 'ArrowUp', 'ArrowDown', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'ArrowLeft', 'ArrowRight', 'b', 'a'];

document.addEventListener('keydown', (e) => {
    konamiCode.push(e.key);
    konamiCode = konamiCode.slice(-10);

    if (konamiCode.join('') === konamiSequence.join('')) {
        // Trigger special animation
        document.body.style.animation = 'rainbow 2s linear infinite';

        setTimeout(() => {
            document.body.style.animation = '';
        }, 5000);
    }
});

// Rainbow animation for easter egg
const style = document.createElement('style');
style.textContent = `
    @keyframes rainbow {
        0% { filter: hue-rotate(0deg); }
        100% { filter: hue-rotate(360deg); }
    }
`;
document.head.appendChild(style);

// ================================
// INITIALIZE
// ================================
console.log('%c🌟 Lumie Health - Built with care for teens', 'color: #F4C14A; font-size: 16px; font-weight: bold;');
console.log('%cHealth that grows with you.', 'color: #9BC4C7; font-size: 12px;');

// Run initial functions
highlightNavigation();
parallaxEffect();

// Ensure videos autoplay on mobile (with user interaction)
document.addEventListener('touchstart', () => {
    if (heroVideo) heroVideo.play();
    bgVideos.forEach(video => video.play());
}, { once: true });
