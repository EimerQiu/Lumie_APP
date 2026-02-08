"""
Test script for Lumie email service
Sends a test email to verify Gmail API integration
"""

import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.services.email_service import EmailService


def send_test_email():
    """Send a test email to ciline@gmail.com"""
    print("=" * 60)
    print("Lumie Email Service - Test Script")
    print("=" * 60)
    print()

    # Initialize email service
    print("📧 Initializing email service...")
    email_service = EmailService()

    # Test recipient
    test_recipient = "ciline@gmail.com"

    print(f"📬 Sending test email to: {test_recipient}")
    print(f"📮 From: {email_service.sender_email}")
    print()

    # Test email content
    html_body = """
    <!DOCTYPE html>
    <html>
    <head>
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                line-height: 1.6;
                color: #333;
                max-width: 600px;
                margin: 0 auto;
                padding: 20px;
            }
            .container {
                background: #ffffff;
                border-radius: 12px;
                padding: 40px;
                box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            }
            .logo {
                text-align: center;
                margin-bottom: 30px;
            }
            .logo h1 {
                color: #4F46E5;
                margin: 0;
                font-size: 36px;
            }
            .status {
                background: #10B981;
                color: white;
                padding: 12px 24px;
                border-radius: 6px;
                text-align: center;
                font-weight: bold;
                margin: 20px 0;
            }
            .info {
                background: #F3F4F6;
                border-left: 4px solid #4F46E5;
                padding: 16px;
                margin: 20px 0;
            }
            .footer {
                margin-top: 40px;
                padding-top: 20px;
                border-top: 1px solid #E5E7EB;
                font-size: 14px;
                color: #6B7280;
                text-align: center;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="logo">
                <h1>🌟 Lumie</h1>
            </div>

            <div class="status">
                ✅ Email Service Test Successful!
            </div>

            <h2>Hello from Lumie Backend! 👋</h2>

            <p>
                This is a test email from the Lumie backend email service.
                If you're seeing this, it means the Gmail API integration is working correctly!
            </p>

            <div class="info">
                <strong>🔧 Test Details:</strong>
                <ul>
                    <li><strong>Service:</strong> Gmail API with Service Account</li>
                    <li><strong>Sender:</strong> lumie@yumo.org</li>
                    <li><strong>Method:</strong> Domain-wide Delegation</li>
                    <li><strong>Server:</strong> 54.193.153.37</li>
                </ul>
            </div>

            <h3>✨ What's Next?</h3>
            <ul>
                <li>✅ Email verification for new users</li>
                <li>✅ Team invitation emails</li>
                <li>✅ Password reset emails</li>
                <li>✅ System notifications</li>
            </ul>

            <p>
                The email service is ready to support all Lumie features! 🚀
            </p>

            <div class="footer">
                <p><strong>Lumie Backend Email Service</strong></p>
                <p>Sent via Gmail API • lumie@yumo.org</p>
                <p>© 2026 Lumie. All rights reserved.</p>
            </div>
        </div>
    </body>
    </html>
    """

    plain_body = """
    Lumie Email Service - Test Successful!

    Hello from Lumie Backend!

    This is a test email from the Lumie backend email service.
    If you're seeing this, it means the Gmail API integration is working correctly!

    Test Details:
    - Service: Gmail API with Service Account
    - Sender: lumie@yumo.org
    - Method: Domain-wide Delegation
    - Server: 54.193.153.37

    What's Next?
    - Email verification for new users
    - Team invitation emails
    - Password reset emails
    - System notifications

    The email service is ready to support all Lumie features!

    ---
    Lumie Backend Email Service
    Sent via Gmail API • lumie@yumo.org
    © 2026 Lumie. All rights reserved.
    """

    # Send email
    success = email_service.send_email(
        to_email=test_recipient,
        subject="🌟 Lumie Email Service - Test Successful!",
        html_body=html_body,
        plain_body=plain_body
    )

    print()
    print("=" * 60)
    if success:
        print("✅ SUCCESS: Test email sent!")
        print(f"📬 Check inbox: {test_recipient}")
    else:
        print("❌ FAILED: Could not send test email")
        print("Please check:")
        print("  1. Service account key file exists")
        print("  2. Domain-wide delegation is configured")
        print("  3. Gmail API is enabled")
    print("=" * 60)

    return success


def send_verification_test():
    """Send a test verification email"""
    print("\n" + "=" * 60)
    print("Testing Verification Email Template")
    print("=" * 60)
    print()

    email_service = EmailService()
    test_recipient = "ciline@gmail.com"
    test_token = "test_verification_token_123456789"

    print(f"📧 Sending verification email to: {test_recipient}")
    success = email_service.send_verification_email(
        to_email=test_recipient,
        verification_token=test_token
    )

    print()
    if success:
        print("✅ Verification email sent successfully!")
    else:
        print("❌ Failed to send verification email")

    return success


def send_invitation_test():
    """Send a test invitation email"""
    print("\n" + "=" * 60)
    print("Testing Team Invitation Email Template")
    print("=" * 60)
    print()

    email_service = EmailService()
    test_recipient = "ciline@gmail.com"

    print(f"📧 Sending invitation email to: {test_recipient}")
    success = email_service.send_invitation_email(
        to_email=test_recipient,
        inviter_name="Yumo Team",
        team_name="Yumo Family",
        invitation_link="https://yumo.org/invite/test_token_123",
        is_registered=False
    )

    print()
    if success:
        print("✅ Invitation email sent successfully!")
    else:
        print("❌ Failed to send invitation email")

    return success


if __name__ == "__main__":
    print("\n🌟 Lumie Email Service Test Suite 🌟\n")

    # Run tests
    test_results = []

    # Test 1: Basic email
    print("Test 1: Basic Email")
    result1 = send_test_email()
    test_results.append(("Basic Email", result1))

    # Test 2: Verification email
    print("\nTest 2: Verification Email")
    result2 = send_verification_test()
    test_results.append(("Verification Email", result2))

    # Test 3: Invitation email
    print("\nTest 3: Team Invitation Email")
    result3 = send_invitation_test()
    test_results.append(("Invitation Email", result3))

    # Summary
    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)
    for test_name, result in test_results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status}: {test_name}")

    passed = sum(1 for _, result in test_results if result)
    total = len(test_results)
    print(f"\nTotal: {passed}/{total} tests passed")
    print("=" * 60)

    sys.exit(0 if passed == total else 1)
