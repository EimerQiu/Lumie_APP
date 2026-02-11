"""
Email Service for Lumie
Sends emails using Gmail API with service account delegation
"""

import base64
import os
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Optional
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError


class EmailService:
    """Service for sending emails via Gmail API"""

    def __init__(self):
        """Initialize email service with Gmail API credentials"""
        # Configuration
        self.service_account_file = os.getenv(
            "GMAIL_SERVICE_ACCOUNT_FILE",
            "/home/ubuntu/secrets/lumie-mailer.json"
        )
        self.sender_email = os.getenv("GMAIL_SENDER_EMAIL", "lumie@yumo.org")
        self.scopes = ["https://www.googleapis.com/auth/gmail.send"]

        # Initialize service (lazy loading)
        self._service = None

    def _get_gmail_service(self):
        """Get Gmail API service with delegated credentials"""
        if self._service is not None:
            return self._service

        try:
            # Load service account credentials
            creds = service_account.Credentials.from_service_account_file(
                self.service_account_file,
                scopes=self.scopes,
            )

            # Delegate to sender email (impersonate lumie@yumo.org)
            delegated_creds = creds.with_subject(self.sender_email)

            # Build Gmail API service
            self._service = build("gmail", "v1", credentials=delegated_creds)
            return self._service

        except FileNotFoundError:
            raise Exception(
                f"Service account key file not found: {self.service_account_file}"
            )
        except Exception as e:
            raise Exception(f"Failed to initialize Gmail service: {str(e)}")

    def send_email(
        self,
        to_email: str,
        subject: str,
        html_body: str,
        plain_body: Optional[str] = None
    ) -> bool:
        """
        Send an email using Gmail API

        Args:
            to_email: Recipient email address
            subject: Email subject
            html_body: HTML content of the email
            plain_body: Plain text fallback (optional)

        Returns:
            True if email sent successfully, False otherwise
        """
        try:
            # Create multipart message
            message = MIMEMultipart("alternative")
            message["to"] = to_email
            message["from"] = self.sender_email
            message["subject"] = subject

            # Add plain text version if provided
            if plain_body:
                part1 = MIMEText(plain_body, "plain", "utf-8")
                message.attach(part1)

            # Add HTML version
            part2 = MIMEText(html_body, "html", "utf-8")
            message.attach(part2)

            # Encode message
            raw_message = base64.urlsafe_b64encode(
                message.as_bytes()
            ).decode("utf-8")

            # Send email
            service = self._get_gmail_service()
            service.users().messages().send(
                userId="me",
                body={"raw": raw_message},
            ).execute()

            print(f"✅ Email sent successfully to {to_email}")
            return True

        except HttpError as e:
            print(f"❌ Gmail API error: {e}")
            return False
        except Exception as e:
            print(f"❌ Failed to send email: {str(e)}")
            return False

    def send_verification_email(self, to_email: str, verification_token: str) -> bool:
        """Send email verification email"""
        # Use yumo.org domain for verification link
        verification_link = f"https://yumo.org/email-verify.html?token={verification_token}"

        html_body = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body {{
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
                    line-height: 1.6;
                    color: #333;
                    max-width: 600px;
                    margin: 0 auto;
                    padding: 20px;
                }}
                .container {{
                    background: #ffffff;
                    border-radius: 8px;
                    padding: 32px;
                    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                }}
                .logo {{
                    text-align: center;
                    margin-bottom: 24px;
                }}
                .logo h1 {{
                    color: #4F46E5;
                    margin: 0;
                    font-size: 28px;
                }}
                h2 {{
                    color: #1F2937;
                    margin-top: 0;
                }}
                .button {{
                    display: inline-block;
                    background: #4F46E5;
                    color: white;
                    padding: 12px 32px;
                    text-decoration: none;
                    border-radius: 6px;
                    margin: 20px 0;
                    font-weight: 600;
                }}
                .button:hover {{
                    background: #4338CA;
                }}
                .footer {{
                    margin-top: 32px;
                    padding-top: 20px;
                    border-top: 1px solid #E5E7EB;
                    font-size: 14px;
                    color: #6B7280;
                    text-align: center;
                }}
                .code {{
                    background: #F3F4F6;
                    padding: 2px 6px;
                    border-radius: 4px;
                    font-family: monospace;
                }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="logo">
                    <h1>Lumie</h1>
                </div>

                <h2>Verify Your Email</h2>

                <p>Welcome to Lumie! Please verify your email address to complete your registration.</p>

                <p style="text-align: center;">
                    <a href="{verification_link}" class="button">Verify My Email</a>
                </p>

                <p style="font-size: 14px; color: #6B7280;">
                    Or copy and paste this link in your browser:<br>
                    <span class="code">{verification_link}</span>
                </p>

                <p style="font-size: 14px; color: #6B7280;">
                    This verification link will expire in 24 hours.
                </p>

                <div class="footer">
                    <p>If you didn't create an account with Lumie, you can safely ignore this email.</p>
                    <p>© 2026 Lumie. All rights reserved.</p>
                </div>
            </div>
        </body>
        </html>
        """

        plain_body = f"""
        Welcome to Lumie!

        Please verify your email address by clicking the link below:
        {verification_link}

        This link will expire in 24 hours.

        If you didn't create an account with Lumie, you can safely ignore this email.

        © 2026 Lumie. All rights reserved.
        """

        return self.send_email(
            to_email=to_email,
            subject="Verify Your Lumie Account",
            html_body=html_body,
            plain_body=plain_body
        )

    def send_invitation_email(
        self,
        to_email: str,
        inviter_name: str,
        team_name: str,
        invitation_link: str,
        is_registered: bool = True
    ) -> bool:
        """Send team invitation email"""

        if is_registered:
            action_text = "Open the Lumie app to accept your invitation."
        else:
            action_text = "Create a free Lumie account to join the team."

        html_body = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body {{
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
                    line-height: 1.6;
                    color: #333;
                    max-width: 600px;
                    margin: 0 auto;
                    padding: 20px;
                }}
                .container {{
                    background: #ffffff;
                    border-radius: 8px;
                    padding: 32px;
                    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                }}
                .logo {{
                    text-align: center;
                    margin-bottom: 24px;
                }}
                .logo h1 {{
                    color: #4F46E5;
                    margin: 0;
                    font-size: 28px;
                }}
                .team-card {{
                    background: #F9FAFB;
                    border: 2px solid #E5E7EB;
                    border-radius: 8px;
                    padding: 20px;
                    margin: 20px 0;
                    text-align: center;
                }}
                .team-name {{
                    font-size: 24px;
                    font-weight: bold;
                    color: #1F2937;
                    margin: 8px 0;
                }}
                .inviter {{
                    color: #6B7280;
                    font-size: 14px;
                }}
                .button {{
                    display: inline-block;
                    background: #4F46E5;
                    color: white;
                    padding: 14px 40px;
                    text-decoration: none;
                    border-radius: 6px;
                    margin: 20px 0;
                    font-weight: 600;
                    font-size: 16px;
                }}
                .button:hover {{
                    background: #4338CA;
                }}
                .footer {{
                    margin-top: 32px;
                    padding-top: 20px;
                    border-top: 1px solid #E5E7EB;
                    font-size: 14px;
                    color: #6B7280;
                    text-align: center;
                }}
                .info-box {{
                    background: #EEF2FF;
                    border-left: 4px solid #4F46E5;
                    padding: 12px 16px;
                    margin: 16px 0;
                    font-size: 14px;
                }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="logo">
                    <h1>Lumie</h1>
                </div>

                <h2>You've Been Invited to Join a Team!</h2>

                <div class="team-card">
                    <div class="team-name">{team_name}</div>
                    <div class="inviter">Invited by {inviter_name}</div>
                </div>

                <p>
                    <strong>{inviter_name}</strong> has invited you to join their team
                    <strong>"{team_name}"</strong> on Lumie.
                </p>

                <div class="info-box">
                    💙 Lumie helps families coordinate health routines, share progress,
                    and stay connected in their wellness journey.
                </div>

                <p style="text-align: center;">
                    <a href="{invitation_link}" class="button">Accept Invitation</a>
                </p>

                <p style="font-size: 14px; color: #6B7280; text-align: center;">
                    {action_text}
                </p>

                <p style="font-size: 12px; color: #9CA3AF; text-align: center;">
                    Or copy this link: <br>
                    {invitation_link}
                </p>

                <p style="font-size: 14px; color: #6B7280;">
                    This invitation expires in 30 days.
                </p>

                <div class="footer">
                    <p>If you don't want to join this team, you can safely ignore this email.</p>
                    <p>© 2026 Lumie. All rights reserved.</p>
                </div>
            </div>
        </body>
        </html>
        """

        plain_body = f"""
        You've Been Invited to Join {team_name} on Lumie!

        {inviter_name} has invited you to join their team "{team_name}" on Lumie.

        Lumie helps families coordinate health routines and stay connected.

        Accept your invitation:
        {invitation_link}

        {action_text}

        This invitation expires in 30 days.

        If you don't want to join this team, you can safely ignore this email.

        © 2026 Lumie. All rights reserved.
        """

        return self.send_email(
            to_email=to_email,
            subject=f"You've been invited to join {team_name} on Lumie",
            html_body=html_body,
            plain_body=plain_body
        )


# Singleton instance
email_service = EmailService()
