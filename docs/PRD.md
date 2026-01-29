# PRD

## User Profile

### 1. Feature Overview

The User Profile feature defines the core identity, role, and baseline attributes of every Lumie user. It is the first required feature in the Lumie app and must be completed before any data collection, analytics, or ring-based features are enabled.

The User Profile serves as the foundation for:
- Secure authentication
- Role-based permissions (Teen vs Parent)
- Longitudinal health and activity tracking
- Family linking and data-sharing controls
- Personalized insights across all Lumie features

This feature supports:
- Teen and Parent account separation
- Secure account creation & login
- Persistent user identity across devices
- Server-side data storage
- Future analytics and AI-driven features

### 2. App Entry & Authentication Flow

#### 2.1 First App Launch (Required)

When a user opens the Lumie app for the first time, they must choose one of the following options:
- Log In
- Sign Up

This entry screen:
- Appears before any account role selection
- Appears before any data collection
- Is required to proceed

#### 2.2 Authentication Paths

**A. Log In Flow**

If the user selects Log In, they must enter:
- Email
- Password

Rules:
- Credentials are validated against existing accounts
- On success, the user is taken directly to their home experience
- On failure, clear error messaging is shown (e.g. incorrect password, account not found)

**B. Sign Up Flow**

If the user selects Sign Up, they must enter:
- Email
- Password
- Confirm Password

Rules:
- Email must be unique
- Password confirmation must match
- Password validation is enforced server-side
- Account creation does not proceed until all fields are valid
- After successful credential creation, the user proceeds to Account Type Selection.

### 3. User Roles & Account Type Selection

#### 3.1 Account Type Selection (Required)

After completing Sign Up, the user must select one account type:
- Teen Account
- Parent Account

This choice:
- Determines required profile fields
- Controls permissions and accessible features
- Cannot be changed later without admin/support intervention

UX Note: Account type selection occurs after Sign Up, but before profile details are collected.

### 4. Purpose & Goals

#### 4.1 Why This Feature Exists

The User Profile is required for:
- Account creation & authentication
- Normalizing all physiological, activity, and sleep data
- Linking sensor data, tests, and historical records to a single user
- Supporting parent–teen relationships
- Enabling longitudinal tracking (e.g. growth, recovery trends)

#### 4.2 Explicit Non-Goals

- No medical diagnosis
- No health scoring or ranking
- No social comparison
- No public profiles or discoverability

### 5. Ring Dependency

| Requirement | Status |
|---|---|
| Lumie Ring Required | ❌ No |
| Works Without Hardware | ✅ Yes |
| Allows Later Ring Pairing | ✅ Yes |

The app must not:
- Require ring pairing during signup
- Block profile creation if no ring exists
- Auto-overwrite profile data when a ring is paired later

### 6. Supported Age Range

Users must be 13 years or older to create an account. Ages below 13 are blocked at signup. There is no enforced upper age limit.

Note: Ages 13–21 represent the primary target demographic, not a technical restriction.

### 7. Data Fields & Requirements

#### 7.1 Required Fields (Teen Account)

| Field | Type | Validation |
|---|---|---|
| Name | String | User-entered |
| Email | Email | Unique, verified |
| Account Role | Enum | teen |
| Age | Integer | ≥ 13 |
| Height | Number | cm or ft/in |
| Weight | Number | kg or lb |

#### 7.2 Optional Fields (Teen Account)

| Field | Type | Notes |
|---|---|---|
| ICD-10 Code | String | Selected only from a searchable ICD-10 reference list (type-ahead). No free-text entry allowed. User confirms selection based on a code provided by a healthcare professional. |
| Personal Advisor Name | String | Optional, informational only |

**ICD-10 Usage Rules (Critical)**
- ICD-10 codes are used only for backend logic
- Exact ICD-10 codes are never displayed to peers or family members
- Codes are mapped internally to high-level, non-clinical condition groups
- ICD-10 selection is optional and can be removed at any time

#### 7.3 Parent Account Fields (Initial MVP)

| Field | Type | Notes |
|---|---|---|
| Name | String | Required |
| Email | Email | Unique, verified |
| Account Role | Enum | parent |
| Age | Integer | Optional — required only if the parent pairs a Lumie Ring |
| Height / Weight | Number | Optional — required only if the parent pairs a Lumie Ring |

**Parent Ring Support**
- Parent accounts may optionally pair a Lumie Ring
- If paired:
  - Parent activity, sleep, and wellness data may be shared with family members (opt-in only)
  - Enables shared progress and "improve together" experiences
- Parents without a ring:
  - Can still view shared teen data (if permitted)
  - Can view medication-reminder completion status

### 8. Functional Requirements

#### 8.1 Profile Creation

Users must be able to:
- Create an account without owning a Lumie Ring
- Complete profile setup after authentication
- Skip optional fields during signup
- Save progress and return later

#### 8.2 Profile Editing

Users must be able to:
- Edit all profile fields at any time
- Update height and weight over time
- View latest values as "current"
- Maintain historical values server-side (not visible in MVP UI)

### 9. Server & Data Architecture

This section defines how user profile data is stored, synchronized, and accessed between client devices and backend services.

#### 9.1 Backend Architecture Overview

The Lumie app uses a client–server architecture consisting of:
- Mobile Client (iOS / Android)
- Backend Web Service (API Layer)
- Persistent Database as the source of truth

All user profile data is owned, validated, and persisted by the backend service.

#### 9.2 Backend Web Server

**Web Framework:** FastAPI (Python)

**Rationale:**
- High-performance, asynchronous web framework
- Strong request and data validation via typed schemas
- Well-suited for data-driven and research-oriented applications
- Easy integration with analytics and future ML workflows

The backend exposes a RESTful API using JSON-based request/response formats.

#### 9.3 Database Selection

**Database Type:** Document-based (NoSQL)

**Database:** MongoDB

**Rationale:**
- Flexible schema supports optional and evolving user profile fields
- Natural fit for user-centric, document-shaped data
- Supports partial updates and efficient indexing by userId
- Scales well for future feature expansion

MongoDB serves as the primary persistent storage and system of record.

#### 9.4 Storage Requirements

Profile data must be stored in two locations:

**Client-side (Local Storage):**
- Used for fast access and offline mode
- Stores the most recent successfully synced profile snapshot
- Treated as a cache, not a source of truth

**Server-side (Primary Storage):**
- MongoDB acts as the single source of truth
- FastAPI validates and persists all updates
- Access controlled via authenticated API requests

#### 9.5 Synchronization Rules

Local profile cache must synchronize with the backend service on:
- User login
- Profile creation
- Profile update
- Network reconnection after offline usage

**Conflict Resolution (MVP):**
- Server data takes precedence
- Client cache is overwritten after successful sync

#### 9.6 Backend Service Responsibilities

The FastAPI backend is responsible for:
- Authentication-bound access control
- Profile creation, retrieval, and updates
- Input validation and schema enforcement
- Timestamp management

**API endpoints (example):**
- POST /profile
- GET /profile
- PUT /profile

#### 9.7 Example Backend Data Model

```
UserProfile {
  userId: string,
  role: "teen" | "parent",
  name: string,
  email: string,
  age: number,
  height: { value: number, unit: "cm" | "ft_in" } | null,
  weight: { value: number, unit: "kg" | "lb" } | null,
  icd10Code: string | null,
  advisorName: string | null,
  createdAt: timestamp,
  updatedAt: timestamp
}
```

Note: Height and weight are nullable to support parent accounts that do not use a ring.

#### 9.8 Historical Data Handling (Non-MVP Detail)

- Historical height and weight updates may be logged separately
- Current profile always reflects latest values
- Historical data reserved for analytics and future features

### 10. Security & Privacy (Teen-First Design)

- No medical claims or diagnoses
- Condition information is represented only by optional ICD-10 code selection
- ICD-10 codes are never shown publicly or to peers
- All profile data is private by default
- No discoverability or sharing without explicit consent
- No comparison, ranking, or leaderboards
- Data access strictly tied to authenticated user and user-controlled family sharing settings

### 11. Error States & Edge Cases

- Email already exists → prompt login
- Age < 13 → block signup with explanation
- Network failure → save locally, sync later
- Switching devices → pull profile from server
- Ring pairing later → must not modify profile fields

### 12. Dependencies & Order of Implementation

This feature must be completed before:
- Ring pairing
- 6MWT
- Activity tracking
- Analytics dashboards
- Parent-teen linking
- Settings

---

## Settings

### 1. Feature Overview

The Settings feature allows users to manage their account, privacy preferences, data permissions, and third-party integrations. This feature acts as the control center for:
- Account-level settings
- Family data visibility rules
- External data sharing (e.g. Apple Health)

### 2. Purpose

Settings exists to:
- Give users (especially teens) control over their data
- Support legal/privacy requirements for minors
- Prevent forced or accidental data sharing
- Centralize all configuration in one place

### 3. Ring Dependency

| Requirement | Status |
|---|---|
| Requires Lumie Ring | ❌ No |
| Works without hardware | ✅ Yes |

### 4. Settings Sections (UI Structure)

#### 4.1 Account Settings

Fields / Actions:
- View email (read-only)
- Change name
- Edit height / weight
- Edit health condition text
- Edit advisor name
- Change password
- Log out

Note: Email & account role cannot be edited.

#### 4.2 Privacy & Data Sharing

Users can control:
- Whether data is shared with family members
- Which categories are shared

**Data Categories (MVP):**
- Profile basics (age range, height, weight)
- Activity data (steps, distance)
- Test results (6MWT, HRR)
- Heart rate data

Each category has:
- Toggle: Share / Don't Share
- Default: Family sharing = OFF
- User must explicitly enable

#### 4.3 Apple Health Integration

**Capabilities:**
- Connect / Disconnect Apple Health
- Select which data types to:
  - Read from Apple Health
  - Write to Apple Health

**Supported Data (Initial):**
- Steps
- Heart rate
- Distance walked

Apple Health permissions must always be revocable.

### 5. Functional Requirements

Users must be able to:
- Modify privacy settings at any time
- Revoke previously granted permissions
- Control family visibility independently from Apple Health
- Have settings changes synced to server immediately

### 6. Server & Data Model (Settings)

```
UserSettings {
  userId: string,
  familySharing: {
    profile: boolean,
    activity: boolean,
    testResults: boolean,
    heartRate: boolean
  },
  appleHealth: {
    connected: boolean,
    readPermissions: string[],
    writePermissions: string[]
  },
  updatedAt: timestamp
}
```

### 7. Safety & Teen Protection

- All sharing is opt-in
- No forced sharing from parents
- Teens can revoke access at any time
- Clear, human-readable explanations (no legal language)

---

## Family System

### 1. Feature Overview

The Family System allows multiple accounts (teens and parents) to join a shared family group in order to view selected health and activity data. Each family:
- Has a unique join code
- Contains multiple members
- Respects individual data-sharing preferences

### 2. Purpose

The Family feature exists to:
- Allow parents to monitor progress (with consent)
- Support teens with coaches/advisors
- Enable shared accountability without public exposure

### 3. Family Creation & Joining

#### 3.1 Create a Family

Any user can:
- Create a family
- Become the Family Owner

System generates:
- A unique family code (e.g. LUMIE-8F2A)

#### 3.2 Join a Family

Users can:
- Tap "Join a Family"
- Enter the family code
- Preview family name & members
- Confirm join

### 4. Family Roles

| Role | Permissions |
|---|---|
| Family Owner | Manage members, regenerate code |
| Member | View shared data only |

Note: No role can override another user's privacy settings.

### 5. Data Visibility Rules (Critical)

Family members can only see:
- Data that the user has explicitly allowed in Settings

If a toggle is OFF:
- Data is hidden
- Appears as "Not shared"

### 6. Family Data Views (UI)

For each family member:
- Name
- Role (Teen / Parent)
- Shared metrics only

Example:
- Steps ✔️
- 6MWT ❌ (Hidden)
- HR ❌ (Hidden)

### 7. Functional Requirements

Users must be able to:
- Join or leave a family at any time
- Change sharing preferences without rejoining
- Be in only one family at a time (MVP)
- See real-time updates when permissions change

### 8. Server Data Models

#### 8.1 Family

```
Family {
  familyId: string,
  familyCode: string,
  ownerId: string,
  members: string[],
  createdAt: timestamp
}
```

#### 8.2 Family Membership

```
FamilyMember {
  familyId: string,
  userId: string,
  role: "owner" | "member",
  joinedAt: timestamp
}
```

### 9. Privacy & Edge Cases

- Leaving a family immediately revokes access
- Regenerating a family code invalidates old codes
- Deleted accounts are auto-removed
- No cross-family visibility

### 10. Dependency Order

This feature requires:
- User Profile
- Settings

This feature must exist before:
- Parent dashboards
- Longitudinal family analytics
- Notifications ("Your child completed a test")

---

## Teen-Friendly Patient Education

### 1. Feature Overview

The Teen-Friendly Patient Education feature translates medical terminology, diagnostic language, and anatomy concepts into clear, calm, age-appropriate explanations designed for teens. The goal is to help users understand what words mean—not to interpret test results, confirm diagnoses, or predict outcomes. This feature is designed to reduce anxiety, replace harmful online searches, and support confidence through understanding.

### 2. Problem Statement

Many teens:
- Do not understand the medical language used in reports or diagnoses
- Encounter frightening or extreme information when searching online
- Feel anxious due to unfamiliar terms rather than actual health risk
- Lack access to explanations written for their age group

This feature provides safe, neutral explanations written as if explaining to a 12-year-old, supported by simple visuals.

### 3. Ring Dependency

| Requirement | Status |
|---|---|
| Lumie Ring Required | ❌ No |
| Hardware-Agnostic | ✅ Yes |

Education content is available regardless of wearable usage.

### 4. Target Users

- Teens aged 13–21
- Users with diagnosed or suspected chronic conditions
- Users who want to understand medical words or body systems

### 5. Content Types

Teen-Friendly Patient Education supports three main content categories:

#### A. Vocabulary & Medical Terms

Examples:
- "renal"
- "peak systolic velocity"
- "superior / inferior"
- "pelvis (renal)"
- "artery / vein"

Each term includes:
- Simple definition
- Everyday analogy (when possible)
- Optional visual reference

#### B. Anatomy Education

Examples:
- Organs (kidneys, heart, lungs)
- Blood flow pathways
- Body orientation (top/bottom, front/back)

Anatomy content:
- Uses simple labeled diagrams
- Avoids medical imaging (no scans, no reports)
- Focuses on what things do, not pathology

#### C. Condition-Related Education

For user-selected condition groups:
- High-level explanation of what the condition affects
- What it usually means
- What it usually does not mean
- No symptoms lists, severity ranking, or outcome framing.

### 6. Explanation Style & Prompt Rules (Critical)

All explanations must follow this instruction:
**"Explain this as you would to a 12-year-old."**

**Mandatory Language Rules:**
- Short sentences
- Simple vocabulary
- Calm, neutral tone
- No statistics
- No rare or extreme cases
- No clinical or diagnostic framing

**Example:**
- Instead of: "Peak systolic velocity measures arterial blood flow during ventricular contraction."
- Use: "This means how fast blood moves through a blood vessel when your heart squeezes."

### 7. Visual Design Requirements

Visuals are a core part of this feature.

**Visual Rules:**
- Flat, illustrated diagrams
- Friendly colors
- Clear labels
- No numbers, measurements, or charts
- No comparison or abnormal indicators

Visuals support:
- Orientation (where things are)
- Function (what things do)
- Vocabulary grounding

### 8. Interaction Design

#### 8.1 On-Demand Explanation

Users can tap on:
- Highlighted words
- Condition names
- Anatomy labels

A modal or card opens with:
- Explanation text
- Optional diagram
- Close button

#### 8.2 Progressive Disclosure

- Default view is short
- Optional "Learn more" expands explanation
- No auto-scrolling or forced reading

### 9. Personalization & Controls

Content is shown only for:
- Terms the user taps
- Conditions the user selects

Users may:
- Disable education cards
- Remove conditions at any time
- No education content is auto-pushed.

### 10. Integration with Other Features

#### A. Advisor

Advisor may ask:
- "Do you want a simple explanation of this term?"
- Advisor may reference education content but does not paraphrase clinically

#### B. Chat

- Education content is not automatically shared
- Users may choose to reference explanations in peer chat

#### C. Profile / ICD-10

- ICD-10 codes are never shown
- Education content is linked only to high-level condition groups

### 11. Safety & Compliance

- No diagnosis
- No interpretation of reports
- No clinical claims
- No personalized risk
- No medical images or documents

### 12. Disclaimer (Shown Before First Use)

**This information is for learning and understanding only. It does not give medical advice or explain test results.**

---

## Activity

### 1. Feature Overview

The Activity feature tracks and summarizes physical movement for teens aged 13–21 with chronic health conditions, using the Lumie Ring as the primary data source. The feature emphasizes balance between activity and rest, not performance or calorie burn. It uses adaptive goals, visual progress indicators, and user confirmation to ensure accuracy without pressure.

### 2. Ring Dependency

| Requirement | Status |
|---|---|
| Ring Required | ✅ Yes |
| Works Without Ring | ❌ No |
| Manual Activity Entry | ⚠️ Fallback only |

The Lumie Ring is required for detecting activity and calculating intensity. Manual entry exists only to prevent gaps when a live activity was not started.

### 3. Target Users

- Teens aged 13–21
- Users with pre-existing chronic health conditions
- Users with a medical diagnosis (optional ICD-10)
- Users wearing a Lumie Ring

### 4. Sub-Features & Requirements

#### 4.1 Activity Time

**Definition:** Activity Time represents the total duration of physical movement recorded within a single calendar day.

**Measurement Scope:**
- Daily aggregate metric
- Automatically calculated

**Data Sources:**
- Ring motion data (IMU)
- Continuous wear detection
- Manual activity entry (fallback only)

**Functional Requirements:**
- System automatically aggregates total active minutes per day
- Daily totals reset at local day boundaries
- Users can view historical daily activity time
- Manual activity is included but clearly marked as estimated

#### 4.2 Activity Intensity

**Definition:** Activity Intensity represents the physiological effort of recorded activity relative to the user's personal baseline, not absolute performance or exercise type. Intensity reflects how demanding the activity is for the individual user.

**Measurement Scope:**
- Calculated per ring-tracked activity segment
- Aggregated into a daily summary

**With Ring (Measured):**

Intensity is derived from:
- Heart rate response
- Motion patterns (IMU)
- Sustained effort duration
- Deviation from the user's historical baseline

**Manual Intensity (Estimated):**

When logging a manual activity, users may optionally select an estimated intensity:
- Low
- Moderate
- High

Rules:
- Clearly labeled Estimated
- Represents perceived effort only
- Carries reduced weight compared to ring-measured intensity
- Never treated as physiological truth

**Intensity Display (Teen-Safe):**

Categorical scale only:
- Low
- Moderate
- High
- No calorie burn
- No MET values
- No performance ranking

**Functional Requirements:**
- Ring-measured intensity is calculated only from ring data
- Manual activity may include estimated intensity
- Intensity comparisons are self-referenced only
- Intensity feeds adaptive goals conservatively

#### 4.3 Adaptive Activity Goals

**Description:** Adaptive Activity Goals provide a personalized daily activity target that adjusts based on recent sleep, prior activity, and recovery patterns. Goals are intended as guidance, not requirements.

**Inputs:**

Goals may adjust based on:
- Previous-day activity duration
- Previous-day activity intensity
- Recent sleep duration
- Recent sleep quality
- User's historical activity baseline
- Habit Tracker inputs (fatigue, workload, optional health logs)
- No population benchmarks or external norms are used.

**Goal Behavior:**
- Recalculated once per day
- May decrease after:
  - Poor sleep
  - High prior-day exertion
  - Elevated fatigue
- May increase after:
  - Adequate sleep
  - Sustained low-to-moderate exertion

#### 4.4 Manual Activity Entry (Fallback)

**Definition:** Manual Activity Entry allows users to log activity after completion when a live activity session was not started. This includes both user-initiated logging and system-detected activity suggestions.

**Manual Entry Scenarios:**

Manual activity entry supports two scenarios:

**Scenario A: Ring Worn, Workout Not Started**
- The Lumie Ring collected physiological and motion data
- No workout session was explicitly started in the app

**Scenario B: Ring Not Worn**
- No ring data is available
- Activity data is fully user-estimated

**Required Manual Inputs:**

Users must provide:
- Activity type (required)
- Start time
- End time or duration

Manual activity cannot be saved without selecting an activity type.

**Activity Type Selection & Suggestion:**

The user must explicitly select an activity type from a predefined list.

If ring data exists (Scenario A), the system may display a suggested activity type, labeled clearly.

**UI Example:**
```
Suggested: Maybe walking
(Estimated based on prior activity patterns)
```

**User Actions (Required):**

The user must choose one:
- ✅ Confirm the suggested activity
- ✏️ Change the activity type, Start time, End Time(Duration)
- ✕ Dismiss the suggestion (no activity logged)

**Rules:**
- Suggestions are optional and not auto-selected
- User must confirm or change the activity type
- All suggested labels are marked as "Estimated"
- The final selected activity type is considered user-confirmed

**Required Manual Inputs (If Confirmed or Added Manually):**
- Activity type (required)
- Start time
- End time or duration
- Optional estimated intensity

Manual activity cannot be saved without selecting an activity type.

**Data Handling Rules:**

**If Ring Data Exists (Scenario A):**
- Heart rate data from the detected window may be displayed
- Motion data may calculate duration
- Intensity may be calculated if sufficient data exists

**If Ring Data Does NOT Exist (Scenario B):**
- No heart rate
- No measured physiological intensity
- Estimated intensity allowed
- Does not contribute to fatigue or recovery models
- All manual entries are labeled Estimated.

**Restrictions (Critical):**
- The system must never assume activity type without user confirmation
- Estimated activity is never treated as fully equivalent to ring-started activity

**Functional Requirements:**
- Manual entry can be user-initiated OR system-suggested (ring detected).
- Activity type selection is mandatory
- Ring-measured data (if available) is automatically attached
- Manual entries are visually distinct from ring-started activities
- Manual entries contribute to:
  - Daily activity time
  - Adaptive activity goals (as estimated input only)

#### 4.5 Six-Minute Walk Test (6MWT)

**Definition:** The Six-Minute Walk Test (6MWT) measures the distance walked in six minutes and is used as a self-referenced functional fitness check-in.

**With Ring (Required):**

The Lumie Ring enables:
- Automatic test timing
- Continuous heart rate tracking
- Pace consistency measurement
- Post-test recovery metrics

**Functional Requirements:**
- Clear step-by-step instructions
- Start/stop controls with countdown timer
- Automatic result storage
- Results compared only to the user's past tests
- No VO₂ max estimation
- No clinical diagnosis or labeling

### 5. Privacy & Safety (Teen-Focused)

- No public leaderboards
- No calorie burn or weight-loss claims
- All activity comparisons are self-referenced only
- Manual entries are clearly labeled and visually distinct
- 6MWT results are informational, not diagnostic

---

## Sleep

### 1. Feature Overview

The Sleep feature tracks and analyzes ring-measured sleep patterns to help teens aged 13–21 with chronic health conditions understand their rest, recovery, and readiness for daily activity. Sleep data is used to:
- Provide clear, non-clinical sleep insights
- Support adaptive activity goals
- Offer context for fatigue and recovery trends

### 2. Ring Dependency

| Requirement | Status |
|---|---|
| Lumie Ring Required | ✅ Yes |
| Works Without Ring | ❌ No |
| Manual Sleep Entry | ❌ Not supported |

**Rationale:** Accurate sleep stage detection and overnight physiological measurements require continuous, passive sensing that can only be provided by the Lumie Ring.

### 3. Target Users

- Teens aged 13–21
- Users with pre-existing chronic health conditions
- Users wearing a Lumie Ring

### 4. Sleep Metrics (Basics)

#### 4.1 Total Sleep Time

**Definition:** Total Sleep Time represents the total duration spent asleep during a sleep period, excluding time awake.

**Functional Requirements:**
- Automatically detected per sleep session
- Displayed in hours and minutes
- Nightly values stored for trend visualization
- No fixed "ideal" duration shown

#### 4.2 Sleep Stages

Sleep stages are estimated using ring-measured physiological signals.

**Stages Displayed:**
- REM Sleep
- Deep Sleep
- Light Sleep

**Functional Requirements:**
- Displayed as duration and percentage of total sleep
- Compared to the user's personal baseline
- No clinical interpretation or disorder labeling
- No universal "normal" ranges shown

#### 4.3 Sleep Timing

**Definition:** Sleep Timing describes when sleep occurs, including onset and wake time.

**Metrics:**
- Bedtime
- Wake time
- Sleep window consistency

**Functional Requirements:**
- Automatically detected
- Visualized across multiple days
- No enforcement of "correct" schedules

### 5. Sleep Target Framework

#### 5.1 Sleep Targets (Age-Aware & Adaptive)

**Definition:** Sleep targets represent personalized reference ranges that indicate how close a user is to their own sleep needs, rather than population ideals.

Targets are:
- Age-aware
- Baseline-adjusted over time
- Self-referenced

**Target Inputs:**

Sleep targets are derived from:
- User age group:
  - 13–15
  - 16–18
  - 19–21
- Historical sleep duration
- Recent sleep consistency
- Long-term averages (not single nights)

#### 5.2 Baseline Adjustment Logic

- Initial sleep targets are set using age-appropriate reference ranges
- Over time, targets gradually adjust toward what is sustainable for the individual
- Baseline updates are slow and conservative to avoid pressure or sudden changes

Example (conceptual):
- If a user consistently sleeps ~7h 30m, the baseline shifts toward that value
- The system avoids labeling consistent patterns as "bad" or "failed"

#### 5.3 Sleep Stage Targeting

Sleep stages are evaluated as:
- Progress toward personal targets
- Relative to the user's own baseline

**Display Examples:**
- "REM sleep: 90% of your usual range"
- "Deep sleep slightly below your recent average"
- ❌ No "normal / abnormal" labels
- ❌ No clinical thresholds

### 6. Sleep Analysis

#### 6.1 Resting Heart Rate (RHR)

**Definition:** Resting Heart Rate (RHR) represents the lowest stable heart rate recorded during sleep, used as a general indicator of overnight recovery.

**Data Source:**
- Continuous heart rate monitoring from the Lumie Ring

**Functional Requirements:**
- Calculated once per sleep session
- Displayed alongside sleep duration
- Compared only to the user's historical baseline

#### 6.2 Sleep Consistency (Derived Metric)

**Definition:** Sleep Consistency reflects how regular sleep timing is across multiple nights.

**Use:**
- Informational only
- Input to adaptive activity goals
- Not displayed as a score or grade

### 7. Integration with Other Features

Sleep data may be referenced by:
- Adaptive Activity Goals (Activity feature)
- Fatigue Index (Feature 4)
- Advisor

---

## Fatigue Index

### 1. Feature Overview

The Fatigue Index is a non-clinical, composite wellness signal that estimates a user's physiological and functional fatigue over time. It combines:
- Continuous heart-rate–derived metrics from the Lumie Ring, and
- Contextual workload information from the app

The Fatigue Index is designed for teens aged 13–21 with chronic health conditions to help them:
- Understand fatigue trends
- Recognize periods of increased strain
- Support safer activity and recovery decisions

The Fatigue Index does not diagnose illness, assess mental health, or provide medical advice.

### 2. Ring Dependency

| Requirement | Status |
|---|---|
| Lumie Ring Required | ✅ Yes |
| Works Without Ring | ❌ No |

**Rationale:** Continuous heart rate (HR) and heart rate variability (HRV) are essential physiological inputs for fatigue estimation.

**If Ring Data Is Unavailable:**
- The Fatigue Index is not calculated
- Contextual workload data may still be logged
- Fatigue insights resume only when ring data is restored

### 3. Target Users

- Teens aged 13–21
- Users with pre-existing chronic health conditions
- Users wearing a Lumie Ring

### 4. Core Concept

Fatigue emerges when workload exceeds recovery capacity over time.

**Key Physiological Pattern:**
Elevated resting heart rate + suppressed HRV + sustained workload → higher fatigue

All calculations are baseline-relative, personalized to the user, and not based on population thresholds.

### 5. Required Inputs

#### 5.1 Mandatory Physiological Inputs (Ring-Based)

These inputs are required to compute the Fatigue Index:

**Resting Heart Rate (RHR):** Overnight average

**Heart Rate Variability (HRV):** Overnight trend relative to personal baseline

If either input is missing, the Fatigue Index is not calculated.

#### 5.2 Contextual Inputs (App-Based)

Contextual inputs enhance interpretation but cannot replace physiological data.

**Automatically Derived:**
- Sleep duration
- Sleep timing and consistency
- Activity duration
- Activity intensity

**Manually Logged (Habit Tracker):**
Workload indicators, including:
- Academic load
- Cognitive effort
- Daily obligations

⚠️ Manual inputs are limited to workload context and cannot independently alter fatigue state.

### 6. Manual Input Restrictions

- Users cannot manually set or edit fatigue levels
- Fatigue Index cannot be increased or decreased by workload input alone
- Physiological signals (HR, HRV) are always required

### 7. Fatigue Index Logic (High-Level)

The Fatigue Index increases when patterns persist across time, including:
- Elevated RHR despite normal or reduced physical activity
- Suppressed HRV during periods of sustained workload
- Poor or inconsistent sleep combined with ongoing workload
- Decline in functional capacity relative to recent activity
- Accumulation of multiple stressors (physical + cognitive)

**Temporal Smoothing:**
- Single-day anomalies are smoothed using rolling averages
- The index reflects multi-day trends, not daily spikes

### 8. Fatigue Index Output

#### 8.1 Display Format

The Fatigue Index is presented as a qualitative state, such as:
- Low
- Moderate
- Elevated
- No numerical score is shown.

#### 8.2 Interpretation Language

Displayed using non-alarming, descriptive phrasing, for example:
- "Higher than your usual level"
- "Similar to your recent baseline"
- "Gradually increasing over the past few days"

❌ The following labels are never used:
- Overtrained
- Burnout
- At risk

### 9. Integration With Other Features

The Fatigue Index may inform:
- Adaptive Activity Goals (Activity feature)
- Sleep Insights (Sleep feature)
- Advisor context (read-only, if shared)

The Fatigue Index:
- May reduce or stabilize activity goals
- Cannot trigger alerts or recommendations
- Cannot generate treatment guidance

### 10. Privacy & Safety (Teen-Focused)

- No fatigue scores, rankings, or leaderboards
- No peer comparison
- No public visibility
- No self-reported fatigue or mood ratings
- Fatigue insights are private by default

### 11. Non-Medical Disclaimer

The Fatigue Index is a wellness insight intended to support self-awareness. It does not diagnose medical conditions, assess mental health, or replace professional care.

---

## Stress / Anxiety

### 1. Feature Overview

The Stress / Anxiety feature provides a non-clinical physiological stress signal derived from heart-rate–based patterns measured by the Lumie Ring. It is designed for teens aged 13–21 with chronic health conditions to help them:
- Recognize periods of elevated physiological stress
- Observe stress patterns across days and weeks
- Understand how daily demands may relate to bodily stress responses

This feature reflects physiological stress only, not emotional state, and does not diagnose anxiety disorders, mental health conditions, or emotional well-being.

### 2. Ring Dependency

| Requirement | Status |
|---|---|
| Lumie Ring Required | ✅ Yes |
| Works Without Ring | ❌ No |
| Manual Stress Input | ❌ Not supported |

**Rationale:** Continuous heart rate and heart rate variability measurements are required to detect autonomic stress patterns reliably.

**If Ring Data Is Unavailable:**
- Stress / Anxiety insights are not calculated
- No estimates or placeholders are displayed

### 3. Target Users

- Teens aged 13–21
- Users with pre-existing chronic health conditions
- Users wearing a Lumie Ring

### 4. Core Concept

Physiological stress is reflected through autonomic nervous system activation, observable via heart-rate dynamics.

**Key Physiological Pattern:**
Elevated heart rate and suppressed HRV during rest or light activity → higher physiological stress

All interpretations are:
- Baseline-relative
- Personalized to the individual
- Based on patterns over time, not single moments

### 5. Required Inputs

#### 5.1 Mandatory Physiological Inputs (Ring-Based)

These inputs are required to compute the Stress / Anxiety signal:

**Resting Heart Rate (RHR):** Overnight baseline

**Resting Heart Rate Variability (HRV):** Overnight trend relative to personal baseline

**Light-Activity Heart Rate:** Heart-rate response during low-intensity movement (e.g., walking)

If any required physiological input is missing, the stress signal is not calculated.

#### 5.2 Contextual Inputs (Optional, App-Based)

These inputs provide interpretive context only and are not required for stress computation.

- Sleep timing and consistency (optional)
- Optional workload indicators from the Habit Tracker:
  - Academic load
  - Cognitive effort
  - Daily obligations

⚠️ Contextual inputs cannot independently raise or lower stress levels and never replace physiological signals. Stress insights are fully functional without workload logs.

### 6. Manual Input Restrictions

- Users cannot manually report stress or anxiety
- No mood ratings or self-reported anxiety scales are used
- Stress levels cannot be set, edited, or overridden by the user
- Logging workload is optional and only affects contextual interpretation when provided
- All stress insights are derived from ring-measured physiological data.

### 7. Stress / Anxiety Logic (High-Level)

The Stress / Anxiety signal increases when patterns persist across time, including:
- Elevated RHR relative to baseline
- Suppressed HRV during rest
- Disproportionately high HR during light activity
- Limited heart-rate recovery after low-effort movement
- Repeated stress signals across multiple days

**Temporal Smoothing:**
- Single-day spikes are smoothed using rolling averages
- Emphasis is placed on multi-day trends, not momentary fluctuations

### 8. Workload–Stress Correlation (Pattern Recognition)

When workload data is available, stress insights may highlight associations between physiological stress signals and periods of increased workload logged in the Habit Tracker.

**Examples:**
- Elevated stress signals appearing on days with higher workload
- Reduced stress signals during lower workload periods

**Important Constraints:**
- Correlations are observational only
- No causal language is used
- Workload logs cannot trigger stress insights on their own
- If no workload data is logged, stress insights rely solely on physiological patterns.

### 9. Stress / Anxiety Output

#### 9.1 Display Format

Stress / Anxiety is presented as a qualitative state, such as:
- Lower than usual
- Typical
- Higher than usual
- No numerical score or percentage is shown.

#### 9.2 Interpretation Language

Insights are displayed using neutral, body-focused phrasing, for example:
- "Your body shows signs of increased stress today"
- "Similar to your recent baseline"
- "Stress signals have been elevated over the past few days"

❌ The following terms are never used:
- Anxiety disorder
- Panic
- Clinical anxiety
- Mental health diagnosis

### 10. Integration With Other Features

The Stress / Anxiety signal may inform:
- Adaptive Activity Goals (Activity feature)
- Fatigue Index (complementary signal)
- Advisor context (read-only, if shared)

Stress insights:
- May reduce or stabilize activity goals
- Cannot trigger alerts or interventions
- Cannot generate treatment recommendations

### 11. Relationship to Fatigue Index

- Fatigue Index reflects cumulative workload versus recovery capacity
- Stress / Anxiety reflects autonomic nervous system activation
- The two signals are:
  - Related but independent
  - Displayed separately
  - Never combined into a single score

### 12. Privacy & Safety (Teen-Focused)

- No stress scores, rankings, or leaderboards
- No peer comparison
- No public visibility
- No labeling of emotional or mental states
- Workload–stress correlations are visible only to the user (and advisor, if shared)
- Users are never required to log workload data

---

## Habit Tracker

### 1. Feature Overview

The Habit Tracker allows users to log simple, optional daily signals that help explain how they are feeling and functioning beyond what wearable data alone can capture. This feature supports:
- Perceived workload
- Self-reported fatigue
- Optional condition-specific manual metrics (e.g. blood pressure)

Habit Tracker inputs are:
- Quick
- Non-judgmental
- User-controlled

Their primary purpose is to contextualize and gently adjust adaptive activity goals, and to improve interpretation of Fatigue Index and Stress / Anxiety trends.

### 2. Ring Dependency

| Requirement | Status |
|---|---|
| Lumie Ring Required | ❌ No |
| Hardware-Agnostic | ✅ Yes |

The Habit Tracker remains fully accessible even if wearable data is unavailable.

### 3. Target Users

- Teens aged 13–21
- Users with chronic health conditions
- Users who want control over how their daily capacity is reflected in goals

### 4. Core Design Principles

- Low friction > high precision
- User perception matters
- User control over adaptation
- Simple inputs that users actually maintain are more valuable than clinically precise data they won't log.

### 5. Logged Signals

#### 5.1 Workload (1–2–3)

**Definition:** Perceived cognitive, academic, or life demand for the day.

| Level | Label | Description |
|---|---|---|
| 1 | Light | Minimal mental or academic demands |
| 2 | Moderate | Typical school day with assignments |
| 3 | Heavy | Exams, deadlines, intense mental focus |

**Rules:**
- Self-defined
- No "correct" level
- No explanation required

#### 5.2 Fatigue (1–2–3)

**Definition:** User's perceived physical and mental tiredness for the day.

| Level | Label | Description |
|---|---|---|
| 1 | Low | Feeling relatively energized |
| 2 | Moderate | Some tiredness, manageable |
| 3 | High | Feeling very tired or drained |

**Rules:**
- Subjective by design
- Independent from ring-calculated Fatigue Index
- Used as a user feedback signal, not a physiological measure

#### 5.3 Condition-Specific Manual Metrics (Optional)

Users may optionally log simple condition-relevant values, such as:
- Blood pressure (for users with hypertension)
- Other basic metrics tied to their selected condition group

**Rules:**
- Entirely optional
- User-entered
- No validation against clinical thresholds
- Compared only to the user's own historical range

### 6. Interaction Design

#### 6.1 Input Method

- Separate, simple cards for:
  - Workload
  - Fatigue
  - Optional condition metric
- Sliders or numeric input (as appropriate)
- Large touch targets

#### 6.2 Time to Log

- ≤ 10 seconds total
- Designed for once-per-day use
- Users may log any subset (not all required)

#### 6.3 Default State

- "Not logged"
- No reminders
- No pressure or penalties

### 7. Functional Requirements

Users can:
- Log workload once per day
- Log fatigue once per day
- Log optional condition metrics when relevant
- Edit or delete same-day entries
- Skip any input entirely

The system:
- Stores trends over time
- Clearly labels all entries as user-reported
- Never generates alerts from manual inputs alone

### 8. Adaptive Activity Goal Adjustment (User-Controlled)

#### 8.1 Role in Activity Goals

Habit Tracker inputs may modulate daily activity goals.

**Examples:**
- Higher reported fatigue → slightly reduced activity goal
- Higher workload → softer intensity expectations
- Manual metrics outside the user's typical range → conservative adjustment

⚠️ These adjustments are:
- Small
- Reversible
- Never mandatory

#### 8.2 User Agency (Critical)

Users can:
- See why a goal was adjusted
- Override or ignore adjustments
- Disable Habit Tracker influence on goals entirely

**Example explanation shown to user:**
"Today's activity goal is slightly lower because you reported higher fatigue."

### 9. Data Behavior & Constraints

Habit Tracker data:
- Does not trigger alerts
- Does not generate medical recommendations
- Does not override ring data
- Does not make safety claims

Manual metrics:
- Are not interpreted clinically
- Are not compared to population norms
- Are never used alone to limit activity

### 10. Integration with Other Features

#### A. Activity
- Habit Tracker inputs gently adjust goals
- User always retains control

#### B. Fatigue Index
- Manual fatigue helps contextualize trends
- Does not replace physiological fatigue signals

#### C. Stress / Anxiety
- Helps distinguish:
  - Cognitive load
  - Life stress
  - Physical strain

#### D. Advisor
- Advisor may reference logged fatigue or metrics
- Uses reflective, non-prescriptive language only

### 11. Privacy & Safety (Teen-Focused)

- Workload data:
  - Is private by default
  - Is not shared with peers
  - Is not visible in chat
- No comparison with other users
- No scoring, ranking, or evaluation
- Users are never required to log workload

---

## Chat

### 1. Feature Overview

The Chat feature provides an optional, moderated peer-support space for teens aged 13–21 with chronic health conditions. Users are matched into group chats based on ICD-10 condition groupings, allowing them to connect with others who share similar lived health experiences.

The purpose of Chat is to enable:
- Emotional support
- Shared coping strategies
- Peer understanding

Chat is not intended for:
- Medical advice
- Diagnosis or treatment discussion
- Health comparison or validation

Participation is opt-in and designed with strict safety controls for minors.

### 2. Ring Dependency

| Ring Required | Status |
|---|---|
| Ring Required | ❌ No |
| Hardware-Agnostic | ✅ Yes |

### 3. Target Users

- Teens aged 13–21
- Users with pre-existing chronic health conditions
- Users who have optionally provided an ICD-10 diagnosis code

### 4. Core Design Principle

Connection through shared condition groups and lived experience — not diagnosis details, metrics, or comparison.

### 5. Sub-Features & Functional Requirements

#### 5.1 Condition-Based Group Chats (ICD-10 Grouping)

**Description:** Users are eligible to join group chats formed by shared ICD-10 condition groups. ICD-10 codes are used only for backend matching and are mapped internally to high-level, non-clinical condition groups. Exact ICD-10 codes are never displayed to other users. Group chats are designed to connect users with similar diagnoses and lived experiences while maintaining privacy and non-clinical framing.

**Grouping Rules:**
- Group assignment is based on the user's selected ICD-10 code
- ICD-10 codes are mapped internally to condition groups
- Users see only the group name, not diagnostic codes
- Group participation is opt-in
- Users may leave a group at any time
- No public group discovery or browsing

**Diagnosis Visibility Control:**

Users may choose whether to explicitly display their diagnosis label in chat.

**Show diagnosis label:**
- Displays a high-level group label (e.g., "Cardiac condition")

**Hide diagnosis label:**
- Displays "Shared condition group"

**Important Clarification:**
Being in the same group inherently implies shared diagnosis context, even if labels are hidden. Visibility settings affect display only, not matching. Users are never required to discuss diagnosis details.

**User-Facing Group Examples:**
- Cardiac conditions group
- Respiratory conditions group
- Neurological conditions group
- Endocrine / metabolic conditions group
- Chronic pain & fatigue group

(Group naming may be adjusted for teen-appropriate language.)

#### 5.2 Group Chat (Moderated)

**Description:** Group chats allow users within the same ICD-10 condition group to communicate in a moderated, shared space. Chats are designed for:
- Emotional support
- Shared experiences
- Coping strategies

Chats are NOT intended for medical advice or diagnosis discussion.

**Functional Requirements:**
- Group chat access limited to users in the same condition group
- Messages visible only to group members
- No public feeds or search
- Messages displayed chronologically
- Users can mute, report, or leave groups at any time

**Moderation & Filtering:**

Automated and manual moderation must block:
- Medical advice, diagnosis, or treatment instructions
- Requests for medical validation or comparison
- Harmful, triggering, or graphic content
- Pressure to disclose diagnosis details or personal information

A disclaimer is shown before first use: "This space is for peer support, not medical advice."

#### 5.3 Friend Requests (Within Condition Groups)

**Description:** Users may send friend requests to other users within the same ICD-10 condition group. Friend connections are optional and user-controlled.

**Rules:**
- Friend requests allowed only within the same condition group
- No public friend lists or follower counts
- Users may:
  - Accept
  - Decline
  - Block friend requests
- Friend connections can be removed at any time

**Safety Constraints:**
- No visibility into mutual friends
- Blocking removes access across group and private chats
- No friend recommendations based on popularity or activity

#### 5.4 Private Chat (PC)

**Description:** Private chat (PC) enables one-to-one messaging between users who have mutually accepted a friend request. Private chat is intended for continued peer conversation, not dependency-forming communication.

**Functional Requirements:**
- Private chat enabled only after mutual friend acceptance
- Text-based messaging by default
- Users can mute, report, or block at any time
- Diagnosis visibility settings apply equally in private chats

**Safety Constraints (Critical):**
- No anonymous private messaging
- No private chat initiation without mutual consent
- Automated moderation applies to private chats
- Rate limits to prevent spam or pressure
- Escalation flow for repeated violations

#### 5.5 Photo Sharing (Group & Private Chat)

**Description:** Users may share limited images from their device photo library in both group chats and private chats to provide non-sensitive context. Photo sharing is optional and restricted.

**Allowed Content:**
- Screenshots of Lumie app data (sleep, activity, trends)
- Non-identifying daily-life images
- Neutral visuals supporting conversation

**Restricted Content (Strictly Enforced):**
- Medical documents, prescriptions, or test results
- Images of injuries, wounds, or medical procedures
- Nudity, sexual, or revealing images
- Personally identifying information (faces discouraged)
- Images intended for comparison or validation

**Functional Requirements:**
- Explicit permission request for photo library access
- Image preview and confirmation before sending
- Automated image moderation
- Sender may delete images at any time
- Recipients cannot download, forward, or reshare images

A warning is shown before first image share: "Please do not share medical images or personal identifying content."

### 6. Privacy & Safety (Critical)

- All chat content is transmitted securely and stored with access controls.
- No public profiles, feeds, or discovery
- ICD-10 codes are never visible in chat
- Diagnosis visibility is user-controlled
- No rankings, reactions, or engagement metrics
- Blocking fully removes visibility and access

---

## Advisor

### 1. Feature Overview

The Advisor feature provides users with an AI-powered advisor chat that references Lumie Ring–derived data and user-approved context to help users:
- Understand trends in activity, sleep, fatigue, stress, and workload
- Reflect on recent changes and patterns
- Receive general, educational recommendations informed by recent research relevant to their condition group

The Advisor is informational and reflective, not diagnostic or prescriptive. It does not provide medical advice, diagnosis, or treatment recommendations.

### 2. Ring Dependency

| Requirement | Status |
|---|---|
| Lumie Ring Required | ✅ Yes |
| Works Without Ring | ❌ No |

**Rationale:** The Advisor relies on continuous physiological data (e.g., HR, HRV, sleep, activity) collected by the Lumie Ring to generate meaningful insights.

**If Ring Data Is Unavailable:**
- Advisor check-ins are paused
- The Advisor informs the user that insufficient data is available
- No speculative or placeholder insights are shown

### 3. Target Users

- Teens aged 13–21
- Users with chronic health conditions
- Users wearing a Lumie Ring
- Users who want data-informed reflection and guidance

### 4. Core Design Principle

Reflection and education > instruction

The Advisor helps users notice patterns and learn from research, not tell them what they must do.

### 5. Advisor Structure

#### 5.1 Check-In Frequency (User-Controlled)

Users choose how often the Advisor initiates a check-in:
- Daily
- Weekly

**Rules:**
- Frequency can be changed at any time
- Check-ins are optional
- Users may pause or disable Advisor check-ins

#### 5.2 System-Initiated Check-Ins

At each scheduled check-in, the Advisor:
- Reviews recent ring-derived data
- Compares trends to the user's personal baseline
- Identifies notable patterns or changes
- Initiates a guided chat conversation

The Advisor initiates conversations only during scheduled check-ins.

#### 5.3 User-Initiated Advisor Chat

Users may open the Advisor chat at any time

User-initiated chats:
- Reference the same ring-derived data
- Do not trigger alerts or new check-in logic

The Advisor does not proactively message users outside scheduled check-ins

### 6. Data Access & Permissions

#### 6.1 Read-Only Data Access

The Advisor may reference the following ring-based data:
- Activity summaries
- Sleep summaries
- Fatigue Index trends
- Stress / Anxiety trends

And optional app-based data:
- Workload (Habit Tracker)
- High-level ICD-10 condition group (optional)

**Rules:**
- Data access is read-only
- Only data explicitly enabled by the user is visible
- ICD-10 codes are never shown, only high-level condition groups

### 7. Advisor Chat Behavior Rules

#### 7.1 Allowed Advisor Behaviors

The Advisor may:
- Point out trends or changes over time
- Compare recent data to the user's baseline
- Highlight correlations (e.g., workload and stress patterns)
- Ask reflective or clarifying questions
- Provide general, educational recommendations based on research

#### 7.2 Prohibited Advisor Behaviors (Critical)

The Advisor must never:
- Provide medical advice or diagnosis
- Interpret ICD-10 codes clinically
- Recommend medications, supplements, or treatments
- Prescribe workouts, intensity limits, or recovery protocols
- Use alarmist, clinical, or judgmental language

### 8. Condition-Aware Educational Recommendations

#### 8.1 Description

When users opt to share their condition group, the Advisor may present high-level, evidence-informed considerations derived from recent peer-reviewed research relevant to that group. These recommendations are:
- General and educational
- Non-prescriptive
- Non-diagnostic
- Framed as considerations, not instructions

#### 8.2 Examples of Allowed Recommendations

- "Some studies suggest that individuals with certain cardiovascular conditions may benefit from moderating sustained high-intensity cardio."
- "Research on chronic fatigue-related conditions often emphasizes pacing and adequate recovery."
- "For some respiratory conditions, consistency in activity may be more important than intensity."

#### 8.3 Examples of Prohibited Recommendations

- ❌ "You should stop cardio."
- ❌ "Heavy training is unsafe for your condition."
- ❌ "Your diagnosis requires avoiding high heart rates."

#### 8.4 Recommendation Triggers

Condition-aware recommendations may appear when:
- The user has opted to share their condition group
- Relevant research exists for that group
- Recent data patterns align with commonly discussed themes in the literature

Recommendations are never triggered solely by diagnosis and never framed as required actions.

#### 8.5 Evidence Transparency

Recommendations may reference:
- Study summaries
- Publication year ranges
- General research context

No clinical guidelines or treatment protocols are cited

### 9. Pattern Identification (Non-Diagnostic)

The Advisor may help users notice potential areas of attention, such as:
- Repeated elevated fatigue trends
- Persistent stress signals during light activity
- Irregular sleep timing
- Sustained workload without recovery

These are presented as patterns to notice, not problems to fix.

### 10. Advisor Output Language

All Advisor responses must:
- Use neutral, supportive tone
- Use observational and conditional language
- Avoid urgency or risk framing

**Example Allowed Phrasing:**
- "Your fatigue has been higher than your usual level this week."
- "Stress signals often appear on days with heavier workload."
- "Some research suggests pacing may be helpful for people with similar conditions."

**Example Prohibited Phrasing:**
- "You should reduce training."
- "This indicates a medical issue."
- "You may have anxiety."

### 11. Integration with Other Features

#### A. Fatigue Index
- Advisor explains relationships between sleep, activity, workload, and fatigue
- Cannot modify fatigue calculations or thresholds

#### B. Stress / Anxiety
- Advisor highlights physiological stress patterns
- Cannot label emotional or mental states

#### C. Habit Tracker
- Advisor references workload patterns if logged
- If no workload is logged, Advisor relies on physiological data only

### 12. Privacy & Safety (Teen-Focused)

- Advisor access is fully user-controlled
- No data is shared externally
- Advisor cannot see peer chat or messages
- Advisor conversations are private
- Users may disable the Advisor at any time

### 13. Non-Medical Disclaimer

Displayed before first Advisor interaction:

**The Advisor provides educational and informational insights only. It does not provide medical advice, diagnosis, or treatment and should not replace guidance from a qualified healthcare professional.**
