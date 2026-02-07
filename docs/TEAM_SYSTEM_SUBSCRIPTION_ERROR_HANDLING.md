# Team System: Subscription Error Handling - Summary of Changes

## Changelog

**v1.2 (2026-02-06):**
- **NEW FEATURE:** Unregistered user invitation flow
- Added invitation tokens (JWT) for secure deep linking
- Added public API endpoint for invitation preview
- Added invitation landing page (web & app deep link)
- Added registration/login with invitation context
- Added post-registration invitation preview screen
- Added Example 5 showing complete unregistered user flow

**v1.1 (2026-02-06):**
- **BREAKING CHANGE:** Removed subscription check on invite side
- Invitations can now be sent to any user regardless of their subscription tier
- Subscription check happens when invitee accepts (better UX)
- Removed `InvitedUserLimitException` - no longer needed
- Updated error flow examples to reflect new behavior

**v1.0 (2026-02-06):**
- Initial version with standardized subscription error responses
- Added upgrade prompts with direct navigation to upgrade screen
- Created reusable `UpgradePromptBottomSheet` component

---

## Overview

This document summarizes the changes made to the Team System design to improve subscription error handling and guide users to upgrade from Free to Pro when they hit subscription limits.

---

## Key Changes

### 1. Standardized Subscription Error Response Format

**Added:** Section 3.0 - Standardized Subscription Error Response

All subscription-related errors now return a consistent JSON structure:

```json
{
  "error": {
    "code": "SUBSCRIPTION_LIMIT_REACHED",
    "message": "You've reached your team limit (1/1 teams)",
    "detail": "Free users can create 1 team. Upgrade to Pro for unlimited teams.",
    "subscription": {
      "current_tier": "free",
      "required_tier": "pro",
      "upgrade_required": true
    },
    "action": {
      "type": "upgrade",
      "label": "Upgrade to Pro",
      "destination": "/subscription/upgrade"
    }
  }
}
```

**Benefits:**
- Frontend can parse error responses consistently
- Contains all information needed to display upgrade prompts
- Includes navigation destination for upgrade flow
- Supports different error codes for different scenarios

---

### 2. Updated API Endpoints

**Modified Endpoints:**

#### POST /api/teams (Create Team)
- ✅ Returns standardized subscription error response
- ✅ Uses `raise_subscription_limit_error()` helper
- ✅ Includes team count in error message

#### POST /api/teams/{team_id}/invite (Invite Member)
- ✅ **NO subscription check** - Invitations can be sent to any user regardless of their subscription tier
- ✅ Subscription check happens when the invitee accepts the invitation
- ✅ This provides better UX - the invitee can make their own decision to upgrade

#### POST /api/teams/{team_id}/accept (Accept Invitation)
- ✅ Returns standardized subscription error response
- ✅ Uses `raise_subscription_limit_error()` helper
- ✅ Includes team count in error message
- ✅ Shows upgrade prompt to invitee if they've reached their team limit

---

### 3. Flutter Error Handling Strategy

**Added:** Section 4.0 - Error Handling Strategy

**New Exception Types:**
```dart
class SubscriptionException implements Exception
class SubscriptionLimitException extends SubscriptionException
```

**Service Layer Updates:**
- TeamService parses 403 errors and throws appropriate exceptions
- Uses `_parseSubscriptionError()` helper to extract error details
- Only checks subscription on CREATE and ACCEPT operations (not INVITE)

**UI Handling Pattern:**
```dart
try {
  // API call (createTeam or acceptInvitation)
} on SubscriptionLimitException catch (e) {
  // Show upgrade prompt with button
} catch (e) {
  // Generic error
}
```

**Subscription Check Locations:**
- ✅ Create Team - Check when user creates a new team
- ✅ Accept Invitation - Check when user accepts an invitation
- ❌ Invite Member - NO check (invitations sent freely)

---

### 4. Updated Screen Designs

#### 4.2 Team List Screen
**Changes:**
- FAB button now checks subscription limit before navigation
- Shows upgrade prompt immediately if Free user has 1 team
- Added `canCreateTeam` and `hasReachedTeamLimit` getters to provider

#### 4.3 Create Team Screen
**Changes:**
- Added comprehensive error handling section
- Shows upgrade modal/bottom sheet for subscription errors
- Includes Flutter implementation example with `_showUpgradeDialog()`

#### 4.5 Invite Member Screen
**Changes:**
- **NO subscription error handling** - Invitations can be sent freely
- Basic validation for email format, user not found, and duplicate invitations
- If invited user has reached their limit, they'll see upgrade prompt when they try to accept
- This provides better UX - doesn't block admins from inviting, lets invitee decide

#### 4.7 Accept Invitation Dialog
**Changes:**
- Added comprehensive error handling section
- Shows upgrade modal/bottom sheet for subscription errors
- Dismisses invitation dialog before showing upgrade prompt
- Includes Flutter implementation example

#### 4.8 Upgrade Prompt Bottom Sheet (NEW)
**New reusable component:**
- Displays subscription error with upgrade call-to-action
- Shows benefits of Pro plan
- Primary button navigates to subscription/upgrade screen
- Secondary button dismisses
- Fully implemented Flutter code provided

---

## Error Flow Examples

### Example 1: Free User Creates Second Team

1. User (Free tier, 1 existing team) taps "Create Team"
2. Fills form and submits
3. Backend returns 403 with `SUBSCRIPTION_LIMIT_REACHED`
4. Frontend catches `SubscriptionLimitException`
5. Shows `UpgradePromptBottomSheet`:
   - Message: "You've reached your team limit (1/1 teams)"
   - Detail: "Free users can create 1 team. Upgrade to Pro for unlimited teams."
   - Button: "Upgrade to Pro" → navigates to `/subscription/upgrade`

### Example 2: Free User Accepts Second Invitation

1. User (Free tier, 1 existing team) taps "Accept" on invitation
2. Backend returns 403 with `SUBSCRIPTION_LIMIT_REACHED`
3. Frontend catches `SubscriptionLimitException`
4. Dismisses invitation dialog
5. Shows `UpgradePromptBottomSheet` (same as Example 1)

### Example 3: Admin Invites Free User at Limit (New Flow)

1. Admin invites user by email
2. Backend creates pending invitation (NO subscription check)
3. Frontend shows success: "Invitation sent to jane@example.com"
4. Invited user (Free tier, 1 existing team) receives invitation
5. Invited user taps "Accept"
6. Backend returns 403 with `SUBSCRIPTION_LIMIT_REACHED`
7. Frontend catches `SubscriptionLimitException`
8. Shows `UpgradePromptBottomSheet` to the **invitee** (not the admin):
   - Message: "You've reached your team limit (1/1 teams)"
   - Detail: "Free users can join 1 team. Upgrade to Pro for unlimited teams."
   - Button: "Upgrade to Pro" → navigates to `/subscription/upgrade`
9. Invitee can now make their own decision to upgrade

**Benefits of this flow:**
- Doesn't block admins from sending invitations
- Puts upgrade decision in hands of the person who needs to upgrade
- Better conversion - user sees value proposition at the moment they want to join

### Example 4: Free User with 1 Team Clicks Create FAB

1. User (Free tier, 1 existing team) clicks "+" FAB on Team List screen
2. Frontend checks `hasReachedTeamLimit` (returns true)
3. Shows `UpgradePromptBottomSheet` immediately
4. Does NOT navigate to Create Team screen
5. User can upgrade or dismiss

---

### Example 5: Unregistered User Receives Invitation (New Feature)

**Scenario:** Admin invites Jane (jane@example.com) who doesn't have a Lumie account yet

**Flow:**

1. **Admin sends invitation:**
   - Admin enters jane@example.com → Clicks "Send Invitation"
   - Backend checks: User not found in database
   - Backend creates pending invitation with email (no user_id)
   - Backend generates invitation token (JWT with team_id and email)
   - Backend sends invitation email with link: `https://lumie.app/invite/{token}`
   - Frontend shows: "Invitation sent to jane@example.com"

2. **Jane receives email:**
   ```
   Subject: You've been invited to join Smith Family on Lumie

   Hi Jane,

   John Smith has invited you to join their team "Smith Family" on Lumie.

   Lumie helps families coordinate health routines and stay connected.

   [Accept Invitation]

   Or copy this link: https://lumie.app/invite/abc123xyz

   This invitation expires in 30 days.
   ```

3. **Jane clicks invitation link:**
   - Opens web page: `https://lumie.app/invite/abc123xyz`
   - Web page calls: `GET /api/teams/invitations/token/abc123xyz` (public endpoint)
   - Shows invitation preview:
     - Team name: "Smith Family"
     - Invited by: "John Smith"
     - Member count: "4 members"
   - Displays options:
     - [Download Lumie App] (primary)
     - [Sign Up on Web] (secondary)
     - "Already have an account? Sign In"

4. **Jane chooses "Download Lumie App":**
   - Downloads from App Store / Play Store
   - Installs app
   - Opens app

5. **Jane opens app for first time:**
   - Sees welcome screen
   - Taps "Create Account"
   - *Jane manually enters the invitation link again* OR *Clicks the email link again*
   - Deep link handler detects: `lumie://invite/abc123xyz`
   - Since Jane not logged in → Navigate to Registration Screen with token context

6. **Registration with invitation context:**
   - Registration screen shows invitation banner:
     - "You're joining Smith Family"
     - "Invited by John Smith"
   - Jane fills registration form:
     - Email: jane@example.com (pre-filled or validated to match invitation)
     - Password: ••••••••
     - Name: Jane Doe
   - Jane taps "Create Account"
   - Backend creates user account
   - Backend links pending invitation to new user_id

7. **Post-registration:**
   - App redirects to Invitation Preview Screen
   - Shows full invitation details
   - Jane taps "Accept Invitation"
   - Backend calls: `POST /api/teams/invitations/token/{token}/accept`
   - Backend checks:
     - ✓ User authenticated
     - ✓ User email matches invitation email
     - ✓ Invitation still pending
     - ✓ Subscription limit check (Jane is Free tier with 0 teams → OK)
   - Backend updates team_member status: pending → member

8. **Success:**
   - Shows success message: "Welcome to Smith Family!"
   - Navigates to Team Detail Screen
   - Jane can now see team members and shared data

**Alternative: Jane Already Has 1 Team (at limit):**

At step 7, if Jane already has 1 team:
- Backend returns: 403 with `SUBSCRIPTION_LIMIT_REACHED`
- Frontend shows `UpgradePromptBottomSheet`:
  - "You've reached your team limit (1/1 teams)"
  - "Upgrade to Pro for unlimited teams"
  - [Upgrade to Pro] → Navigate to subscription upgrade
- Jane can decide to upgrade before accepting

**Benefits:**
- Seamless onboarding for new users
- Invitation context preserved throughout registration
- Clear value proposition (joining a team)
- Upgrade prompt shown at the right moment (when value is clear)

---

## Implementation Checklist

### Backend Tasks
- [ ] Add `SubscriptionErrorDetail` and related Pydantic models
- [ ] Create `raise_subscription_limit_error()` helper function
- [ ] Update POST /api/teams to use standardized error response
- [ ] Update POST /api/teams/{team_id}/invite to:
  - REMOVE subscription check (send invitations freely)
  - Support inviting unregistered users by email
  - Generate invitation tokens (JWT)
  - Send invitation emails with deep links
- [ ] Update POST /api/teams/{team_id}/accept to use standardized error response
- [ ] Add GET /api/teams/invitations/token/{token} (public endpoint for invitation preview)
- [ ] Add POST /api/teams/invitations/token/{token}/accept (accept via token)
- [ ] Create `generate_invitation_token()` and `decode_invitation_token()` helpers
- [ ] Update email service to send invitation emails with links
- [ ] Add database support for pending invitations by email (no user_id)
- [ ] Add unit tests for subscription error responses
- [ ] Add unit tests for invitation token generation/validation

### Frontend Tasks
- [ ] Add `SubscriptionErrorResponse`, `SubscriptionInfo`, `SubscriptionAction` Dart models
- [ ] Add `SubscriptionException` and `SubscriptionLimitException` classes (NO InvitedUserLimitException)
- [ ] Update TeamService to parse and throw appropriate exceptions
- [ ] Update TeamService.inviteMember() to remove subscription error handling
- [ ] Create `UpgradePromptBottomSheet` reusable widget
- [ ] Update Create Team Screen error handling
- [ ] Update Accept Invitation Dialog error handling
- [ ] Update Invite Member Screen to remove subscription error handling (basic validation only)
- [ ] Update Team List Screen FAB behavior
- [ ] Implement deep link handler for invitation links (`lumie://invite/{token}`)
- [ ] Create Invitation Landing Page (web view)
- [ ] Create Invitation Preview Screen (post-registration)
- [ ] Update Registration Screen to support invitation context
- [ ] Update Login Screen to support invitation context
- [ ] Add TeamService methods:
  - `getInvitationByToken(token)`
  - `acceptInvitationByToken(token)`
- [ ] Add navigation route for `/subscription/upgrade`
- [ ] Add navigation route for `/invitation/preview`
- [ ] Add unit tests for error handling logic
- [ ] Add widget tests for `UpgradePromptBottomSheet`
- [ ] Add widget tests for Invitation Preview Screen
- [ ] Test deep link handling

---

## Benefits of This Design

1. **Consistent UX:** All subscription errors are handled the same way across the app
2. **Clear Call-to-Action:** Users always see an "Upgrade to Pro" button when they hit limits
3. **Reduced Friction:** Users can upgrade directly from the error prompt
4. **Better Conversion:** Making upgrade path obvious increases conversion rates
5. **User Empowerment:** Invitations sent freely; upgrade prompt shown to the person who benefits (invitee, not admin)
6. **Reduced Admin Friction:** Admins can invite anyone without worrying about subscription status
7. **Higher Engagement:** Free users receive invitations, see value, then decide to upgrade
8. **Maintainable:** Centralized error response format and reusable components
9. **Extensible:** Easy to add new subscription-gated features in the future
10. **Type-Safe:** Strongly typed error responses and exceptions prevent bugs

---

## Future Enhancements

1. **A/B Testing:** Test different upgrade prompt designs and messaging
2. **Analytics:** Track how many users hit limits and upgrade
3. **Personalization:** Customize upgrade prompts based on user behavior
4. **Trial Offers:** Show trial offers when users hit limits
5. **Feature Comparison:** Add detailed Free vs Pro comparison in upgrade prompt
6. **Social Proof:** Show testimonials or user count in upgrade prompt

---

**Document Version:** 1.2
**Last Updated:** 2026-02-06
**Author:** Claude Code Assistant
**Status:** Ready for Implementation
