Olympus — Comprehensive Technical Specification
Part 4: Communication, Assets, Fleet, Travel & Expense, Reports, Integrations, Settings, Security, API Contracts, Frontend Architecture
________________________________________
MODULE 15: COMMUNICATION
15.1 Notices (/notices)
Page subtitle: "Company announcements and policy updates"

KPI Stats: TOTAL | PINNED | ACTIVE | THIS MONTH

Button: + New Notice

________________________________________
New Notice Form:
Field	Type	Options / Notes
Title	text	Required
Category	select	General / Policy Update / Event / Urgent / HR Notice / Safety
Body	rich text editor	(bold, italic, bullet lists, links)
Target Audience	radio	All Employees / Specific Department / Specific Branch / Specific Employees
Department	multi-select	shown if target = dept
Branch	multi-select	shown if target = branch
Employees	multi-select	shown if target = specific
Pin this notice	toggle	shown at top of portal
Publish immediately	toggle	default: on
Publish Date	datetime	shown if immediate = off
Expiry Date	datetime	optional
Attachment	file upload	optional PDF/image

________________________________________
Notices Table columns:
Column	Notes
TITLE	+ pinned badge if pinned
CATEGORY	Badge
TARGET	All / Dept / Branch
PUBLISHED	Date
EXPIRES	Date or "Never"
STATUS	Draft / Active / Expired
ACTIONS	Edit / Pin / Delete / Preview

________________________________________
15.2 Helpdesk (/helpdesk)
Subtitle: "Internal support ticketing system"

KPI Stats: OPEN | IN PROGRESS | SLA BREACH | MY TICKETS | RESOLVED TODAY

Button: + New Ticket

________________________________________
New Ticket Form:
Field	Type	Options
Subject	text	Required
Category	select	IT Support / HR Query / Payroll Issue / Leave Query / Asset Request / Facilities / Other
Priority	select	Low / Medium (default) / High / Critical
Description	textarea	
Attachments	file upload	multiple
Assign To	combobox	(Admin only)

________________________________________
Helpdesk Table columns:
Column	Notes
TICKET ID	#001, #002...
SUBJECT	
SUBMITTED BY	Employee name
CATEGORY	Badge
PRIORITY	Low/Medium/High/Critical badge
ASSIGNED TO	HR officer name
STATUS	Open / In Progress / Resolved / Closed
SLA DUE	Deadline timestamp
CREATED	Date
ACTIONS	View / Assign / Resolve

SLA Rules (configurable): | Priority | Response SLA | Resolution SLA | |---|---|---| | Critical | 1 hour | 4 hours | | High | 4 hours | 24 hours | | Medium | 24 hours | 72 hours | | Low | 72 hours | 7 days |

________________________________________
15.3 Password Requests (/password-requests)
Subtitle: "Employee portal password reset requests"

KPI Stats: PENDING | RESOLVED | ALL CLEAR badge

Table columns: EMPLOYEE | REQUESTED AT | STATUS | ACTIONS (Reset / Dismiss)

________________________________________
MODULE 16: ASSETS (/assets)
16.1 Asset Registry
Subtitle: "Track company assets assigned to employees"

KPI Stats: TOTAL ASSETS | ASSIGNED | AVAILABLE | IN MAINTENANCE | DISPOSED

Button: + Add Asset

________________________________________
Add Asset Form:
Field	Type	Options / Placeholder
Asset Tag	text	"e.g. LAPTOP-001"
Asset Name	text	"e.g. Dell Latitude 5430"
Category	select	Laptop / Desktop / Mobile / Printer / Furniture / Vehicle / Equipment / Other
Serial Number	text	optional
Purchase Date	date	
Purchase Cost (৳)	number	
Warranty Expiry	date	optional
Branch	combobox	
Department	combobox	
Condition	select	New / Good / Fair / Poor
Notes	textarea	

________________________________________
Asset Table columns:
Column	Notes
ASSET TAG	Unique ID
NAME	
CATEGORY	Badge
SERIAL	
ASSIGNED TO	Employee name or "Unassigned"
BRANCH	
STATUS	Available / Assigned / Maintenance / Disposed
PURCHASE COST	৳
ACTIONS	Assign / Edit / Maintenance / Dispose

________________________________________
Assign Asset Form:
Field	Type
Assign To	combobox (employee)
Assignment Date	date
Notes	textarea
Condition on Handover	select
Acknowledgement required	toggle

________________________________________
16.2 Asset Requests (/asset-requests)
Button: + New Request
Asset Request Form (Employee self-service):
Field	Type
Asset Type Requested	text / combobox
Purpose	textarea
Priority	select: Low / Normal / Urgent
Required By Date	date

Request Table columns: EMPLOYEE | ASSET TYPE | PURPOSE | PRIORITY | REQUESTED | STATUS | ACTIONS

________________________________________
MODULE 17: FLEET MANAGEMENT
17.1 Vehicles (/vehicles)
Subtitle: "Manage company fleet, documents and driver assignments"

KPI Stats: TOTAL VEHICLES | ACTIVE | IN SERVICE | DOCUMENT EXPIRING

Button: + Add Vehicle

________________________________________
Add Vehicle Form:
Field	Type	Options
Registration Number	text	Required
Make	text	e.g. "Toyota"
Model	text	e.g. "Hiace"
Year	number	
Vehicle Type	select	Car / Microbus / Van / Truck / Motorcycle / Other
Color	text	
Fuel Type	select	Petrol / Diesel / CNG / Electric
Seating Capacity	number	
Assigned Driver	combobox	employee list (filtered by role=driver)
Branch	combobox	
Status	select	Active / In Maintenance / Decommissioned

________________________________________
Documents (per vehicle — sub-section):
Document	Expiry Field
Fitness Certificate	date
Registration (BRTA)	date
Insurance	date
Route Permit	date
Tax Token	date

________________________________________
Vehicles Table columns:
Column	Notes
REG. NO	
MAKE / MODEL	
TYPE	
DRIVER	Assigned driver name
BRANCH	
STATUS	
NEXT EXPIRY	Earliest document expiry
ACTIONS	Edit / Documents / Maintenance / Decommission

________________________________________
17.2 Drivers (/drivers)
Subtitle: "Driver roster and license management"

Drivers are employees with role/designation = Driver.

Drivers Table columns: | Column | Notes | |---|---| | DRIVER | Employee avatar + name | | LICENSE NO | | | LICENSE TYPE | Class A / B / C | | LICENSE EXPIRY | Date + expiry badge | | ASSIGNED VEHICLE | Registration no | | STATUS | Active / Off Duty / On Leave |

________________________________________
MODULE 18: TRAVEL & EXPENSE
18.1 Conveyance Bills (/conveyance-bills)
Subtitle: "Employee travel expense claims"

KPI Stats: PENDING BILLS | APPROVED | TOTAL AMOUNT THIS MONTH (৳)

Button: + New Claim

________________________________________
Conveyance Claim Form:
Field	Type	Options
Employee	combobox	(admin mode)
Trip Date	date	
From	text	
To	text	
Purpose	text	
Mode	select	CNG / Rickshaw / Taxi / Uber / Bus / Own Vehicle / Other
Distance (km)	number	optional
Amount (৳)	number	Required
Receipt	file upload	optional
Notes	textarea	

________________________________________
Conveyance Table columns:
Column	Notes
EMPLOYEE	
DATE	
FROM → TO	Route
MODE	
AMOUNT	৳
STATUS	Pending / Approved / Rejected / Paid
SUBMITTED	Date
ACTIONS	Approve / Reject / Pay

________________________________________
18.2 Visits (/visits)
Subtitle: "Field visit log and tracking"

Button: + Log Visit
Visit Log Form:
Field	Type
Employee	combobox
Visit Date	date
Client / Location	text
Purpose	textarea
Check-in Time	time
Check-out Time	time
GPS Location (auto)	map pin
Notes	textarea

Visits Table columns: EMPLOYEE | DATE | LOCATION | PURPOSE | CHECK-IN | CHECK-OUT | DURATION | STATUS | ACTIONS

________________________________________
MODULE 19: REPORTS & INSIGHTS (/reports)
Page title: "Overview & Analytics" Subtitle: "High-level analytics across the HR stack"

Filters: | Filter | Type | Default | |---|---|---| | FROM | date | 30 days ago | | TO | date | today | | EMPLOYEE | combobox | All Employees (N) | | TYPE | select | All Types | | QUICK | Presets button | — |

Quick Presets: This Month / Last Month / This Quarter / Last Quarter / This Year / Custom

________________________________________
Report Types Available (TYPE dropdown):
Report	Description	Export
Attendance Trend	Daily present/absent/late rates over date range	CSV / XLSX
Attendance Detail	Per-employee day-by-day attendance log	CSV / XLSX
Late Arrival Report	Employees by late frequency + minutes	CSV
Overtime Report	OT hours and cost by employee and department	CSV / XLSX
Payroll Summary	Gross/deductions/net per employee per month	XLSX / PDF
Payslip Batch	All payslips for a payroll run	PDF (ZIP)
Leave Utilisation	Leave days used vs. entitlement by type	CSV / XLSX
Leave Balance	Current leave balance snapshot	CSV
Workforce Headcount	Active / inactive by department / branch	CSV / XLSX
Workforce Turnover	Joiners, leavers, attrition rate	XLSX
Tax & TDS Report	Monthly TDS deducted per employee	XLSX
TDS Certificate	NBR Form-16 equivalent per employee	PDF
PF Statement	Employee + employer contributions	XLSX
Gratuity Register	All employees with gratuity calculation	XLSX
BEFTN Bank File	Bangladesh Bank EFTN flat file for salary disbursement	TXT
bKash Bulk CSV	bKash B2C bulk payment file	CSV
Nagad Bulk CSV	Nagad bulk payment file	CSV
Asset Register	Full asset list with assignments	XLSX
Vehicle Document Expiry	Fleet documents expiring within N days	CSV
Performance Summary	Ratings and review completion rates	XLSX
Training Completion	Training enrolled/completed by employee	CSV

________________________________________
MODULE 20: INTEGRATIONS (/integrations)
Subtitle: "Public API · Webhooks · Accounting (Tally & QuickBooks)"

Tabs: API Keys | Webhooks | Accounting

________________________________________
20.1 API Keys Tab
Public API Endpoint:

https://uqxkczspnnhkyiljmivz.supabase.co/functions/v1/hrm-public-api

Auth: Header x-api-key: YOUR_API_KEY · Default limit: 100, Max: 500

Full API endpoint list (from page):

GET /hrm-public-api/employees

GET /hrm-public-api/attendance?from=YYYY-MM-DD&to=YYYY-MM-DD

GET /hrm-public-api/payroll?month=1&year=2026

cURL example (shown on page):

curl -H "x-api-key: YOUR_API_KEY" \

     -H "Content-Type: application/json" \

     "https://uqxkczspnnhkyiljmivz.supabase.co/functions/v1/hrm-public-api/employees"

Button: API Reference

API Keys Table columns: NAME | KEY (masked) | PERMISSIONS | LAST USED | CREATED | ACTIONS

Create API Key Form: | Field | Type | |---|---| | Key Name | text | | Permissions | multi-select: read / write | | Expiry | select: Never / 30d / 90d / 1 year |

________________________________________
20.2 Webhooks Tab
Button: + Add Webhook
Add Webhook Form:
Field	Type	Notes
Endpoint URL	url	Must be HTTPS
Events	multi-select	See events list below
Secret (optional)	text	For HMAC-SHA256 signature verification

Webhook Events available: | Event | Trigger | |---|---| | employee.created | New employee added | | employee.updated | Employee profile updated | | employee.terminated | Employee status set to terminated | | attendance.checkin | Employee checks in | | attendance.checkout | Employee checks out | | leave.requested | New leave application submitted | | leave.approved | Leave request approved | | leave.rejected | Leave request rejected | | payroll.generated | Payroll run created | | payroll.finalized | Payroll run finalized | | payroll.paid | Payslip marked as paid |

Webhook payload format:

{

  "event": "attendance.checkin",

  "timestamp": "2026-08-19T09:03:22+06:00",

  "org_id": "uuid",

  "data": {

    "employee_id": "uuid",

    "employee_code": "EMP001",

    "check_in": "2026-08-19T09:03:22+06:00",

    "source": "biometric",

    "device_sn": "ABC123"

  }

}

Webhook delivery: HTTP POST · 3 retries with exponential backoff · X-AIHRBD-Signature header (HMAC-SHA256)

________________________________________
20.3 Accounting Tab
Accounting integrations: Tally · QuickBooks
Tally Integration:
Field	Type
Tally Server URL	text (e.g. http://localhost:9000)
Company Name (in Tally)	text
Sync payroll entries	toggle
Sync frequency	select: Manual / After each payroll run

Data synced to Tally: Payroll journal entries (salary expense, PF, TDS payable accounts)
QuickBooks Integration:
Field	Type
Connect QuickBooks	OAuth2 button
Company	display (after OAuth)
Salary Expense Account	combobox (QBO chart of accounts)
Payroll Liability Account	combobox
Sync	toggle

________________________________________
MODULE 21: SETTINGS (COMPLETE) (/settings)
Tabs: Account | Preferences | Layout | Work Schedule | Leave Quotas | Payroll | Daily Email | Email Templates

________________________________________
21.1 Account Tab
Field	Type	Notes
Avatar	image upload	JPG/PNG max 5MB
Display Name	text	
Email	text	(read-only — linked to Supabase auth)
Role	display	Admin badge
Company	display	
Change Password	button	→ email-based reset flow
Mobile App	section	Install AIHR BD on phone · QR code + App Store/Play Store links

________________________________________
21.2 Preferences Tab
Setting	Type	Default
Language	select	English (EN) / Bengali (BN)
Timezone	select	Asia/Dhaka (UTC+6)
Date Format	select	DD/MM/YYYY / MM/DD/YYYY / YYYY-MM-DD
Time Format	select	12-hour / 24-hour
First Day of Week	select	Sunday / Monday
Currency Display	select	Symbol (৳) / Code (BDT)
Theme	select	System / Light / Dark

________________________________________
21.3 Layout Tab
Dashboard Widget Customization:

-	Toggle individual widgets on/off (all 37 widgets listed)
-	Drag-to-reorder

________________________________________
21.4 Work Schedule Tab
(Detailed in Module 9)

________________________________________
21.5 Leave Quotas Tab
(Detailed in Module 9 and Module 11)

________________________________________
21.6 Payroll Tab
(Detailed in Module 12)

________________________________________
21.7 Daily Email Tab
Description: "Auto-send daily HR summary to managers"

Setting	Type
Enable daily email	toggle
Send time	time picker
Recipients	multi-select (employees / roles)
Include sections	checkboxes: Attendance summary / Absent employees / Pending leaves / Pending approvals

________________________________________
21.8 Email Templates Tab
Templates available (customizable): | Template | When sent | |---|---| | Welcome / Portal Invite | When employee portal access is created | | Leave Approved | When leave is approved | | Leave Rejected | When leave is rejected | | Payslip Ready | When payroll run is finalized | | Birthday Greeting | On employee birthday | | Work Anniversary | On service anniversary | | Probation Ending Soon | 7 days before probation end | | Document Expiry Alert | 30 days before document expiry |

Template Editor fields: | Field | Type | |---|---| | Subject line | text (with {{variables}}) | | Body | rich text (HTML email) | | Available variables | display: {{employee_name}}, {{company_name}}, {{leave_type}}, {{leave_dates}}, {{payslip_month}}, etc. |

________________________________________
MODULE 22: SECURITY (/security)
Subtitle: "Access control, sessions and audit log"

Tabs: Access Control | Sessions | Audit Log

________________________________________
22.1 Access Control
Setting	Type	Notes
Two-Factor Authentication (2FA)	toggle	Enforced for all admin accounts
2FA Method	select	Authenticator App / SMS OTP
Allowed IP Addresses	textarea	Comma-separated CIDRs — blank = all IPs allowed
Session Timeout	select	1 hour / 4 hours / 8 hours / 24 hours / Never
Password Policy	section	
— Min length	number	default: 8
— Require uppercase	toggle	
— Require number	toggle	
— Require special char	toggle	
— Password expiry (days)	number	0 = never
Login Attempts before lockout	number	default: 5
Account lockout duration (minutes)	number	default: 30

________________________________________
22.2 Sessions
Table columns: USER | DEVICE | IP ADDRESS | LOCATION | LAST ACTIVE | ACTIONS (Revoke)

Button: Revoke All Sessions

________________________________________
22.3 Audit Log
Table columns: | Column | Notes | |---|---| | ACTION | e.g. "Employee Created", "Payroll Generated", "Leave Approved" | | PERFORMED BY | User name + role | | TARGET | Entity affected (Employee: EMP001) | | IP ADDRESS | | | TIMESTAMP | |

Filters: Date range | User | Action type | Export CSV

________________________________________
MODULE 23: SYSTEM SETTINGS (/system)
Subtitle: "Organization profile, company settings"

________________________________________
Company Profile Section:
Field	Type
Company Name	text
Company Logo	image upload
Industry	select (RMG / Manufacturing / IT / Banking / NGO / Education / Other)
Company Size	select (1–50 / 51–200 / 201–1000 / 1000+)
Registration Number	text
TIN (Company)	text
Address	textarea
City	text
Website	url
Founded Year	number

________________________________________
Fiscal Year Settings:
Field	Type	Default
Fiscal Year Start Month	select	July (BD standard)
Working Week	checkboxes	Mon–Fri (default)
Public Holiday Calendar	select	Bangladesh (default)

________________________________________
Notification Settings:
Notification	Channel	Toggle
New employee joined	Email + In-app	✅
Leave request received	Email + In-app	✅
Attendance alert (late/absent)	In-app	✅
Payroll generated	Email + In-app	✅
Document expiring soon	Email + In-app	✅
Birthday reminders	In-app	✅

________________________________________
COMPLETE REST API SPECIFICATION
Base URL
https://aihrbd.com/api        (Next.js API routes — internal)

https://uqxkczspnnhkyiljmivz.supabase.co/functions/v1/hrm-public-api  (public)
Auth
All internal routes: Authorization: Bearer {supabase_jwt} Public API: x-api-key: {api_key}

________________________________________
Full API Route Table
# ─── AUTHENTICATION ───────────────────────────────────────────

POST   /api/auth/login                  Login with email+password

POST   /api/auth/logout                 Logout (revoke session)

POST   /api/auth/refresh                Refresh JWT token

POST   /api/auth/reset-password         Send reset email

POST   /api/auth/confirm-reset          Confirm reset with token + new password

GET    /api/auth/me                     Get current user + org context

# ─── EMPLOYEES ────────────────────────────────────────────────

GET    /api/employees                   List (filters: status, dept, branch, type)

POST   /api/employees                   Create employee (step 1+2 combined)

GET    /api/employees/:id               Get full employee profile

PUT    /api/employees/:id               Update employee

DELETE /api/employees/:id               Soft-delete (sets status=terminated)

POST   /api/employees/bulk-import       CSV upload + mapping

GET    /api/employees/:id/attendance    Monthly attendance (query: month, year)

GET    /api/employees/:id/salary-history Payslip list

GET    /api/employees/:id/leave-balance  Leave balances (query: year)

POST   /api/employees/:id/increment     Add salary increment

POST   /api/employees/:id/portal-access Assign/revoke portal login

GET    /api/employees/:id/documents     Employee documents

POST   /api/employees/:id/documents     Upload document

DELETE /api/employees/:id/documents/:docId

GET    /api/employees/:id/education     Education records

POST   /api/employees/:id/education     Add education record

PUT    /api/employees/:id/financial     Update bank/MFS/PF/gratuity settings

# ─── ORGANIZATION ─────────────────────────────────────────────

GET    /api/departments                 List departments

POST   /api/departments                 Create

PUT    /api/departments/:id             Update

DELETE /api/departments/:id

GET    /api/designations                List

POST   /api/designations

PUT    /api/designations/:id

DELETE /api/designations/:id

GET    /api/branches                    List

POST   /api/branches

PUT    /api/branches/:id

DELETE /api/branches/:id

GET    /api/currencies                  List exchange rates

POST   /api/currencies                  Add rate

PUT    /api/currencies/:code            Update rate

# ─── ATTENDANCE ───────────────────────────────────────────────

GET    /api/attendance                  List (filters: date, employee, branch, status)

POST   /api/attendance/manual-punch     Manual check-in or check-out

PUT    /api/attendance/:id              Update attendance record

GET    /api/attendance/summary          Aggregate summary (query: month, year)

POST   /api/attendance/reconcile        Submit reconciliation request

GET    /api/attendance/reconciliation   List reconciliation requests

PUT    /api/attendance/reconciliation/:id/approve

PUT    /api/attendance/reconciliation/:id/reject

GET    /api/devices                     List biometric devices

POST   /api/devices                     Add device

PUT    /api/devices/:id                 Update device config

DELETE /api/devices/:id

POST   /api/devices/:id/sync            Trigger device sync

GET    /api/geofences                   List

POST   /api/geofences                   Create

PUT    /api/geofences/:id

DELETE /api/geofences/:id

GET    /api/qr-codes                    List QR check-in codes

POST   /api/qr-codes                    Generate QR

DELETE /api/qr-codes/:id               Deactivate

POST   /api/qr-checkin                  Employee scans QR code (public-facing)

# ─── BIOMETRIC PUSH (device-facing) ──────────────────────────

POST   /api/iclock/cdata                ZKTeco ADMS push

GET    /api/iclock/getrequest           ZKTeco heartbeat

POST   /api/iclock/devicecmd            ZKTeco command response

POST   /api/hikvision/event             Hikvision ISAPI event push

POST   /api/dahua/event                 Dahua CGI event push

POST   /api/tipsoi/push                 Tipsoi TCP-over-HTTP push

# ─── TIME MANAGEMENT ──────────────────────────────────────────

GET    /api/shifts                      List

POST   /api/shifts                      Create

PUT    /api/shifts/:id

DELETE /api/shifts/:id

GET    /api/roster                      Get roster (query: week, branch, dept)

POST   /api/roster/assign               Assign shift to employee for dates

DELETE /api/roster/:id                  Remove assignment

GET    /api/shift-swaps                 List

POST   /api/shift-swaps                 Create swap request

PUT    /api/shift-swaps/:id/respond     Target employee accepts/rejects

PUT    /api/shift-swaps/:id/approve     HR approves

PUT    /api/shift-swaps/:id/reject      HR rejects

GET    /api/overtime                    List OT records

POST   /api/overtime                    Add manual OT

PUT    /api/overtime/:id/approve

GET    /api/overtime/policy             Get OT policy

PUT    /api/overtime/policy             Update OT policy

GET    /api/breaks                      List break records

POST   /api/breaks/start                Start break

POST   /api/breaks/:id/end              End break

PUT    /api/breaks/:id/approve

# ─── LEAVE ───────────────────────────────────────────────────

GET    /api/leave                       List (filters: status, employee, type, date range)

POST   /api/leave                       Apply leave

GET    /api/leave/:id                   Get detail

PUT    /api/leave/:id/approve           Manager approve

PUT    /api/leave/:id/final-approve     HR final approve

PUT    /api/leave/:id/reject            Reject

DELETE /api/leave/:id                   Cancel (by employee, if still pending)

GET    /api/leave/types                 List leave types

POST   /api/leave/types                 Create custom type

PUT    /api/leave/types/:id

GET    /api/leave/balances              Get balances (query: employee_id, year)

POST   /api/leave/balances/recalculate  Trigger accrual recalculation

GET    /api/holidays                    List

POST   /api/holidays                    Add

PUT    /api/holidays/:id

DELETE /api/holidays/:id

# ─── PAYROLL ─────────────────────────────────────────────────

GET    /api/payroll                     List runs (query: month, year)

POST   /api/payroll/generate            Create payroll run

GET    /api/payroll/:id                 Get run detail

POST   /api/payroll/:id/finalize        Finalize payroll

GET    /api/payroll/:id/slips           List slips for run

GET    /api/payroll/slips/:id           Individual slip detail

PUT    /api/payroll/slips/:id/mark-paid Mark as paid

POST   /api/payroll/slips/bulk-pay      Bulk mark paid

GET    /api/salary-templates            List

POST   /api/salary-templates            Create

PUT    /api/salary-templates/:id

DELETE /api/salary-templates/:id

GET    /api/bonuses

POST   /api/bonuses

PUT    /api/bonuses/:id

DELETE /api/bonuses/:id

GET    /api/meals                       List meal records

GET    /api/meals/summary               Monthly summary

GET    /api/payroll/settings            Get payroll settings

PUT    /api/payroll/settings            Update

# ─── COMPLIANCE ──────────────────────────────────────────────

GET    /api/tax/settings                Get NBR settings

PUT    /api/tax/settings

GET    /api/tax/profiles                List employee tax profiles

POST   /api/tax/profiles                Create / update profile

GET    /api/tax/calculate               Calculate tax (query params)

GET    /api/tax/slabs                   Get slab table (fiscal year)

GET    /api/pf/settings

PUT    /api/pf/settings

GET    /api/pf/ledger                   List (query: employee_id, year)

GET    /api/gratuity/settings

PUT    /api/gratuity/settings

GET    /api/gratuity/calculate          Calculate F&F (query: employee_id, leaving_date)

GET    /api/hours-compliance            Compliance report

GET    /api/grievances                  List

POST   /api/grievances                  Submit

PUT    /api/grievances/:id/assign

PUT    /api/grievances/:id/resolve

GET    /api/committees                  List

POST   /api/committees

PUT    /api/committees/:id

# ─── PERFORMANCE ─────────────────────────────────────────────

GET    /api/performance/cycles

POST   /api/performance/cycles

PUT    /api/performance/cycles/:id

GET    /api/performance/reviews

POST   /api/performance/reviews

PUT    /api/performance/reviews/:id/submit

PUT    /api/performance/reviews/:id/acknowledge

GET    /api/performance/templates

POST   /api/performance/templates

GET    /api/goals                       List (query: employee_id, cycle_id)

POST   /api/goals

PUT    /api/goals/:id

PUT    /api/goals/:id/progress          Update progress %

GET    /api/kudos

POST   /api/kudos

GET    /api/one-on-ones

POST   /api/one-on-ones

PUT    /api/one-on-ones/:id

GET    /api/training

POST   /api/training

PUT    /api/training/:id

POST   /api/training/:id/enroll         Enroll employees

PUT    /api/training/enrollments/:id    Update completion/score

# ─── COMMUNICATION ───────────────────────────────────────────

GET    /api/notices

POST   /api/notices

PUT    /api/notices/:id

DELETE /api/notices/:id

PUT    /api/notices/:id/pin

GET    /api/helpdesk

POST   /api/helpdesk

PUT    /api/helpdesk/:id/assign

PUT    /api/helpdesk/:id/resolve

GET    /api/password-requests

POST   /api/password-requests/:id/reset

# ─── ASSETS ──────────────────────────────────────────────────

GET    /api/assets

POST   /api/assets

PUT    /api/assets/:id

DELETE /api/assets/:id

POST   /api/assets/:id/assign

POST   /api/assets/:id/return

PUT    /api/assets/:id/maintenance

GET    /api/asset-requests

POST   /api/asset-requests

PUT    /api/asset-requests/:id/approve

PUT    /api/asset-requests/:id/reject

# ─── FLEET ───────────────────────────────────────────────────

GET    /api/vehicles

POST   /api/vehicles

PUT    /api/vehicles/:id

DELETE /api/vehicles/:id

GET    /api/drivers                     List driver employees

GET    /api/visits

POST   /api/visits

PUT    /api/visits/:id

# ─── TRAVEL & EXPENSE ────────────────────────────────────────

GET    /api/conveyance-bills

POST   /api/conveyance-bills

PUT    /api/conveyance-bills/:id/approve

PUT    /api/conveyance-bills/:id/reject

PUT    /api/conveyance-bills/:id/pay

# ─── REPORTS ─────────────────────────────────────────────────

GET    /api/reports/attendance          Query + export

GET    /api/reports/payroll             Query + export

GET    /api/reports/leave               Query + export

GET    /api/reports/tax                 Query + export

GET    /api/reports/pf                  PF statement

GET    /api/reports/gratuity            Gratuity register

GET    /api/reports/workforce           Headcount / turnover

GET    /api/reports/performance         Performance summary

GET    /api/reports/training            Training completion

GET    /api/reports/beftn               Generate BEFTN bank file (payroll_run_id)

GET    /api/reports/bkash-bulk          Generate bKash bulk payment CSV

GET    /api/reports/nagad-bulk          Generate Nagad bulk payment CSV

# ─── INTEGRATIONS ────────────────────────────────────────────

GET    /api/integrations/api-keys

POST   /api/integrations/api-keys

DELETE /api/integrations/api-keys/:id

GET    /api/integrations/webhooks

POST   /api/integrations/webhooks

PUT    /api/integrations/webhooks/:id

DELETE /api/integrations/webhooks/:id

POST   /api/integrations/webhooks/:id/test

GET    /api/integrations/accounting/tally

PUT    /api/integrations/accounting/tally

GET    /api/integrations/accounting/quickbooks

POST   /api/integrations/accounting/quickbooks/connect  (OAuth2 initiate)

GET    /api/integrations/accounting/quickbooks/callback (OAuth2 callback)

# ─── SETTINGS & SECURITY ─────────────────────────────────────

GET    /api/settings                    Get all settings

PUT    /api/settings/account

PUT    /api/settings/preferences

PUT    /api/settings/schedule

PUT    /api/settings/leave-quotas

PUT    /api/settings/payroll

PUT    /api/settings/daily-email

GET    /api/settings/email-templates

PUT    /api/settings/email-templates/:id

GET    /api/security/sessions           Active sessions

DELETE /api/security/sessions/:id       Revoke session

DELETE /api/security/sessions           Revoke all

GET    /api/security/audit-log          Query audit log

PUT    /api/security/access-control     Update 2FA, IP whitelist, password policy

# ─── PUBLIC API (Supabase Edge Functions) ─────────────────────

GET    /hrm-public-api/employees        All employees (with x-api-key)

GET    /hrm-public-api/attendance       ?from=&to= attendance log

GET    /hrm-public-api/payroll          ?month=&year= payroll run

________________________________________
FRONTEND ARCHITECTURE (Next.js 14 App Router)
Full Directory Structure
aihrbd/

├── app/

│   ├── (auth)/

│   │   ├── layout.tsx

│   │   ├── login/page.tsx

│   │   └── reset-password/page.tsx

│   ├── (app)/                          # Shell layout

│   │   ├── layout.tsx                  # Sidebar + Topbar + Auth guard

│   │   ├── page.tsx                    # Dashboard (/)

│   │   ├── employees/

│   │   │   ├── page.tsx                # List

│   │   │   ├── new/page.tsx            # Add wizard

│   │   │   └── [id]/

│   │   │       ├── page.tsx            # Profile

│   │   │       └── edit/page.tsx

│   │   ├── organization/page.tsx

│   │   ├── branches/page.tsx

│   │   ├── directory/page.tsx

│   │   ├── documents/page.tsx

│   │   ├── recruitment/page.tsx

│   │   ├── onboarding/page.tsx

│   │   ├── offboarding/page.tsx

│   │   ├── attendance/page.tsx

│   │   ├── reconciliation/page.tsx

│   │   ├── qr-check-in/page.tsx

│   │   ├── devices/page.tsx

│   │   ├── geofences/page.tsx

│   │   ├── live-tracking/page.tsx

│   │   ├── shifts/page.tsx

│   │   ├── roster/page.tsx

│   │   ├── shift-swaps/page.tsx

│   │   ├── overtime/page.tsx

│   │   ├── breaks/page.tsx

│   │   ├── leave/page.tsx

│   │   ├── holidays/page.tsx

│   │   ├── payroll/page.tsx

│   │   ├── salary-templates/page.tsx

│   │   ├── bonuses/page.tsx

│   │   ├── meals/page.tsx

│   │   ├── compliance/page.tsx         # Tax & TDS

│   │   ├── provident-fund/page.tsx

│   │   ├── gratuity/page.tsx

│   │   ├── hours-compliance/page.tsx

│   │   ├── grievance/page.tsx

│   │   ├── committees/page.tsx

│   │   ├── performance/page.tsx

│   │   ├── goals/page.tsx

│   │   ├── kudos/page.tsx

│   │   ├── one-on-ones/page.tsx

│   │   ├── training/page.tsx

│   │   ├── notices/page.tsx

│   │   ├── helpdesk/page.tsx

│   │   ├── password-requests/page.tsx

│   │   ├── assets/page.tsx

│   │   ├── asset-requests/page.tsx

│   │   ├── vehicles/page.tsx

│   │   ├── drivers/page.tsx

│   │   ├── conveyance-bills/page.tsx

│   │   ├── visits/page.tsx

│   │   ├── reports/page.tsx

│   │   ├── integrations/page.tsx

│   │   ├── settings/page.tsx

│   │   ├── security/page.tsx

│   │   ├── system/page.tsx

│   │   └── my-profile/page.tsx

│   └── api/

│       └── [...route]/route.ts         # API router

├── components/

│   ├── ui/                             # Primitives

│   │   ├── Button.tsx

│   │   ├── Input.tsx

│   │   ├── Select.tsx

│   │   ├── Combobox.tsx

│   │   ├── Modal.tsx

│   │   ├── SlideOver.tsx

│   │   ├── Badge.tsx

│   │   ├── Toggle.tsx

│   │   ├── DatePicker.tsx

│   │   ├── TimePicker.tsx

│   │   ├── FileUpload.tsx

│   │   ├── RichTextEditor.tsx

│   │   ├── Table.tsx

│   │   ├── KPICard.tsx

│   │   ├── Tabs.tsx

│   │   └── Avatar.tsx

│   ├── layout/

│   │   ├── Sidebar.tsx                 # Main nav + collapse

│   │   ├── Topbar.tsx                  # Search, weather, date, notifications, user menu

│   │   └── MobileNav.tsx              # Bottom nav: Dashboard/People/Attendance/Payroll/Profile

│   ├── dashboard/

│   │   ├── KPIGrid.tsx                 # 37-widget customizable grid

│   │   ├── AttendanceTrendChart.tsx    # Recharts Area/Bar/Line

│   │   ├── WorkforceCompositionChart.tsx

│   │   ├── TodaysStatusChart.tsx

│   │   ├── WeekdayPatternChart.tsx

│   │   ├── PerformancePulseGauge.tsx

│   │   ├── PrayerTimesCard.tsx         # Dhaka salah times + Hijri date

│   │   ├── MissedAttendanceWidget.tsx

│   │   └── DashboardCustomizer.tsx     # Widget toggle + reorder

│   ├── employees/

│   │   ├── EmployeeTable.tsx

│   │   ├── AddEmployeeWizard.tsx       # 2-step form

│   │   ├── EmployeeProfileTabs.tsx

│   │   ├── ShiftAssignmentTab.tsx

│   │   ├── AttendanceTab.tsx

│   │   ├── FinancialTab.tsx

│   │   └── BulkImport.tsx

│   ├── attendance/

│   │   ├── AttendanceTable.tsx

│   │   ├── ManualPunchModal.tsx

│   │   ├── ReconcileForm.tsx

│   │   ├── DeviceCard.tsx

│   │   ├── AddDeviceForm.tsx           # 4 device types

│   │   ├── GeofenceMap.tsx             # Leaflet map + radius circle

│   │   └── LiveTrackingMap.tsx

│   ├── time/

│   │   ├── ShiftForm.tsx               # Full shift config

│   │   ├── RosterGrid.tsx              # Weekly grid

│   │   ├── OvertimePolicySelector.tsx  # 6 presets

│   │   └── BreakTimer.tsx

│   ├── leave/

│   │   ├── LeaveCalendar.tsx           # Monthly calendar

│   │   ├── ApplyLeaveForm.tsx

│   │   └── LeaveBalanceCard.tsx

│   ├── payroll/

│   │   ├── PayrollTable.tsx

│   │   ├── GeneratePayrollDialog.tsx

│   │   ├── PayslipView.tsx             # Preview + Print + PDF

│   │   ├── SalaryTemplateBuilder.tsx   # Dynamic component rows

│   │   ├── BonusForm.tsx

│   │   └── MFSDisbursementPanel.tsx    # bKash/Nagad/Rocket

│   ├── compliance/

│   │   ├── TaxSettingsForm.tsx         # NBR slab table

│   │   ├── TaxProfileTable.tsx

│   │   ├── TaxCalculator.tsx           # Interactive calculator

│   │   ├── PFSettings.tsx

│   │   ├── GratuitySettings.tsx

│   │   └── FFSettlementCalc.tsx

│   ├── performance/

│   │   ├── ReviewCycleForm.tsx

│   │   ├── ReviewTemplateBuilder.tsx

│   │   ├── ReviewForm.tsx              # Criteria scoring

│   │   ├── GoalCard.tsx

│   │   └── KudosFeed.tsx

│   └── charts/                         # Recharts wrappers

│       ├── AreaChart.tsx

│       ├── BarChart.tsx

│       ├── DonutChart.tsx

│       ├── GaugeChart.tsx

│       └── ScatterChart.tsx

├── hooks/

│   ├── useEmployee.ts

│   ├── useAttendance.ts

│   ├── usePayroll.ts

│   ├── useLeave.ts

│   ├── useTax.ts

│   ├── useOrg.ts

│   └── useAuth.ts

├── lib/

│   ├── supabase/

│   │   ├── client.ts                   # Browser client

│   │   └── server.ts                   # Server component client

│   ├── engines/

│   │   ├── payroll.ts                  # Full payroll computation

│   │   ├── tax.ts                      # NBR TDS engine

│   │   ├── leave.ts                    # Accrual + balance

│   │   ├── gratuity.ts                 # F&F settlement

│   │   └── attendance.ts               # Shift matching + OT

│   ├── exporters/

│   │   ├── beftn.ts                    # BEFTN fixed-width file

│   │   ├── bkash.ts                    # bKash B2C CSV

│   │   ├── nagad.ts                    # Nagad bulk CSV

│   │   └── payslip-pdf.ts             # PDF generation

│   └── mfs/

│       ├── bkash-client.ts

│       └── nagad-client.ts

├── store/

│   ├── authStore.ts                    # Zustand: user, role, orgId

│   ├── orgStore.ts                     # Tenant config cache

│   └── uiStore.ts                      # Sidebar open/close, theme

├── types/

│   ├── employee.ts

│   ├── attendance.ts

│   ├── payroll.ts

│   ├── leave.ts

│   ├── compliance.ts

│   ├── performance.ts

│   └── org.ts

└── supabase/

    ├── functions/

    │   ├── zkteco-push/index.ts

    │   ├── hikvision-push/index.ts

    │   ├── dahua-push/index.ts

    │   ├── tipsoi-push/index.ts

    │   ├── process-attendance/index.ts

    │   └── hrm-public-api/index.ts

    └── migrations/

        ├── 001_initial_schema.sql

        ├── 002_leave_types_seed.sql

        ├── 003_tax_slabs_seed.sql

        ├── 004_holidays_seed.sql

        └── 005_rls_policies.sql

________________________________________
MFS PAYMENT EXPORTERS — COMPLETE CODE
bKash B2C Bulk CSV Format
MerchantInvoiceNumber,ReceiverMSISDN,Amount

PAY-AUG2026-EMP001,01712345678,15000.00

PAY-AUG2026-EMP002,01898765432,22000.00
Nagad Bulk CSV Format
mobile_number,amount,invoice_id,remarks

01712345678,15000.00,NAGAD-AUG2026-001,August 2026 Salary
BEFTN Fixed-Width File Structure
Record Type 1 (File Header):    1 + YYYYMMDD(8) + RoutingNo(9) + AcctNo(17) + CompanyName(25) + RecordCount(6) + TotalAmountPaisa(15)

Record Type 6 (Detail):         6 + SeqNo(7) + TxnCode(2) + AmountPaisa(10) + BeneRoutingNo(9) + BeneAcctNo(17) + BeneName(25) + RefNo(16)

Record Type 9 (File Trailer):   9 + RecordCount(6) + TotalAmountPaisa(15)

________________________________________
DEPLOYMENT CONFIGURATION
Environment Variables
# Supabase

NEXT_PUBLIC_SUPABASE_URL=https://uqxkczspnnhkyiljmivz.supabase.co

NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon_key>

SUPABASE_SERVICE_ROLE_KEY=<service_role_key>

# MFS

BKASH_APP_KEY=<key>

BKASH_APP_SECRET=<secret>

BKASH_USERNAME=<username>

BKASH_PASSWORD=<password>

BKASH_MERCHANT_NUMBER=01XXXXXXXXX

NAGAD_MERCHANT_ID=<id>

NAGAD_API_KEY=<key>

NAGAD_PUBLIC_KEY=<rsa_public_key>

# Maps

NEXT_PUBLIC_GOOGLE_MAPS_KEY=<key>   # OR Leaflet/OSM (no key needed)

# Email

SMTP_HOST=smtp.sendgrid.net

SMTP_PORT=587

SMTP_USER=apikey

SMTP_PASS=<sendgrid_api_key>

SMTP_FROM=noreply@aihrbd.com

# Accounting

QUICKBOOKS_CLIENT_ID=<id>

QUICKBOOKS_CLIENT_SECRET=<secret>

QUICKBOOKS_REDIRECT_URI=https://aihrbd.com/api/integrations/accounting/quickbooks/callback
Infrastructure Diagram
┌─────────────────────────────────────────────────────┐

│              Vercel (Next.js 14)                     │

│  Edge Network — CDN — SSR + API Routes              │

└────────────────┬────────────────────────────────────┘

                 │ HTTPS / WebSocket

┌────────────────▼────────────────────────────────────┐

│         Supabase  (uqxkczspnnhkyiljmivz)            │

│                                                      │

│  ┌────────────┐  ┌──────────────┐  ┌────────────┐  │

│  │ PostgreSQL │  │ Edge Functions│  │  Storage   │  │

│  │ (PostGIS  │  │ (Deno 1.x)   │  │ (S3 API)   │  │

│  │  for GPS) │  │               │  │            │  │

│  └────────────┘  └──────────────┘  └────────────┘  │

│  ┌────────────┐  ┌──────────────┐                   │

│  │ Supabase   │  │  Realtime    │                   │

│  │ Auth (JWT) │  │ (WebSockets) │                   │

│  └────────────┘  └──────────────┘                   │

└─────────────────────────────────────────────────────┘

        │                │             │

┌───────▼──────┐  ┌──────▼──────┐  ┌──▼──────────────┐

│ ZKTeco ADMS  │  │  Hikvision  │  │  Dahua / Tipsoi  │

│ TCP 4370     │  │  ISAPI/80   │  │  HTTP Push       │

└──────────────┘  └─────────────┘  └─────────────────-┘

        │

┌───────▼──────────────────────────────────────────┐

│  MFS Gateways: bKash API / Nagad API / Rocket    │

│  Bank: BEFTN File → Bangladesh Bank              │

│  Accounting: Tally (local) / QuickBooks (cloud)  │

└──────────────────────────────────────────────────┘

