# AIHR BD — Part 1 Architecture

*Foundation · Organization · Employees — Version 1.0 — October 2026 — built from the decisions agreed in the design discussion*

## 0. How to use this document

Give Claude this document plus **one build step at a time** (Section 8). After every step: test by hand, commit, then move on. Anything not written here is outside Part 1. Where this document marks an item as an **assumption**, it is listed in Section 9 for confirmation.

## 1. Scope and final decisions

**In Part 1:** organizations, login and roles, multi-tenant isolation, departments, designations, grades, branches, offices, operations, employees (list, filter, 2-step add, edit, deactivate, profile), nominees, employment history, reporting chain, portal access, audit log.

**Not in Part 1:** shift, attendance, salary, increments, documents, education, bulk import, directory, recruitment, onboarding, offboarding, payroll, leave.

| Topic | Final decision |
| --- | --- |
| Hierarchy | Organization → Branch → Office. No sub-branches. Departments are separate. |
| Tenancy | Every business table carries org\_id. A person has one active employment (one company) at a time. |
| Internal ID | Every user and record has a UUID. All links use UUIDs. Never shown to people. |
| Login | One login page for everyone. Email or mobile number + password. |
| Employee card ID | 8–10 digits. For ID cards, QR and display only. Unique inside one organization, may repeat across organizations. Never used for login or for security lookups. |
| Org ID | 6-digit numeric, random, system-generated, unique, never changes. |
| Grades | EM0–EM4 (employees), MS0–MS2 (management), OWNER01–OWNER02 (owners). Seniority only, no permissions. Attached to the designation. |
| Roles | Separate table. Admin can create roles. A role holds permissions and field visibility. |
| Manager | Can see the whole company's people list. Sensitive fields are controlled per role by the Admin. |
| History | Employment history log (where an employee was and is now) and reporting-chain history. |
| Audit | Append-only security log, kept at least 3 years. |
| Deletion | Soft delete only. |
| Address / nominee | Address stays on the employee profile. Nominees are a separate table linked by employee. |
| Branch/office deactivation | Admin picks a target branch from a dropdown. Employees are transferred there. The transfer is logged. |

## 2. Backend

### 2.1 Principles

- Stack: Supabase (PostgreSQL, Auth, Edge Functions) with Next.js. Server-only secrets never reach the browser.
- Every business table has: UUID primary key, org\_id, created\_at, updated\_at, created\_by, updated\_by, and a status or deleted\_at column for soft delete.
- Isolation is enforced by the database (row-level security), never only by the screen.
- Every change to important data writes an audit log row in the same transaction.
- Text columns for codes and IDs, so leading zeros are never lost.

### 2.2 Tables

**Tenancy and identity**

| Table | Key columns | Notes |
| --- | --- | --- |
| organizations | id, org\_code (6-digit, unique, immutable), name, status, timezone, card\_id\_policy settings | One row per company. |
| user\_profiles | id (same as login user id), email (nullable), phone (nullable, stored as +880…), full\_name, status, must\_change\_password, last\_login\_at, role\_id | One row per login identity. At least one of email or phone is required. Both must be unique across the whole system. |
| employees | id, org\_id, user\_id (nullable), card\_id, full\_name, phone, date\_of\_birth, gender, marital\_status, religion, blood\_group, join\_date, employment\_type, status, department\_id, designation\_id, branch\_id, office\_id, operation\_id, present\_address, permanent\_address, probation fields | One row per employment. An employee can exist before a login is assigned. |
| employee\_sensitive | employee\_id, org\_id, nid\_number (more later: salary, bank) | Kept in its own table so access can be blocked by role. |
| employee\_nominees | id, org\_id, employee\_id, name, phone, relation | Many nominees per employee allowed. |

**Roles and permissions**

| Table | Key columns | Notes |
| --- | --- | --- |
| roles | id, org\_id, name, is\_system, status | Default roles: Admin, HR Manager, Manager, Employee. Admin can add more. |
| permissions | key, module, description | Fixed catalog, for example employees.view, employees.create, org.manage, roles.manage, audit.view. |
| role\_permissions | role\_id, permission\_key | What a role may do. |
| role\_field\_access | role\_id, resource, field\_key, can\_view, can\_edit | The Admin's checkboxes: which fields a role may see or edit. |

**Organization structure**

| Table | Key columns | Notes |
| --- | --- | --- |
| branches | id, org\_id, name, code, address, phone, head\_employee\_id, status | Branch or factory. |
| offices | id, org\_id, branch\_id, name, code, layout, address, status | Every office belongs to one branch. |
| operations | id, org\_id, name, status | Defined by each company, no fixed list. |
| office\_operations | office\_id, operation\_id | Which operations run in which office. |
| departments | id, org\_id, name, description, head\_employee\_id, status | Organization-wide. |
| grades | id, org\_id, code, category (EM, MS, OWNER), level, status | The list is data, so adding MS3 later needs no schema change. |
| designations | id, org\_id, department\_id, grade\_id, name, description, status | Grade comes from the designation. |

**History and audit**

| Table | Key columns | Notes |
| --- | --- | --- |
| employment\_history | id, org\_id, employee\_id, event\_type (joined, transfer, promotion, designation, grade, department, office, status), from values, to values, effective\_date, reason, created\_by | HR record of where the employee was and is now. |
| reporting\_lines | id, org\_id, employee\_id, manager\_employee\_id, line\_type (Reporting Manager, Supervisor, IT Manager, Finance Manager), start\_date, end\_date | End date empty means current. Changing a manager closes the old row and opens a new one. |
| audit\_logs | id, org\_id, actor\_user\_id, action, entity, entity\_id, old\_value, new\_value, ip, created\_at | Append-only. Nobody can edit or delete. |

### 2.3 Employee card ID rules

- 8–10 digits, auto-generated by default (assumption: joining year as 2 digits plus random digits; the organization chooses the total length inside 8–10).
- An organization may instead enter its own ID: 6–15 letters, numbers or hyphen.
- Unique per organization (org\_id + card\_id together). The same number in two organizations is allowed.
- Auto-generation retries on collision and is safe when two people are added at the same moment.
- It is shown on ID cards and QR. A QR scan always runs inside a known organization.
- Department, branch and office are not part of the ID. They are tracked in history tables.
- A transfer to another company creates a new employment with a new card ID.

### 2.4 Login and authentication

- One login field accepts email or mobile number. The system detects which.
- Phone numbers are stored in one standard format (+880…) so one number cannot create two accounts. A number can belong to only one login.
- Adding an employee with portal access creates the login with a first password given by the company. The user must change it at first login.
- Employees without email log in with their mobile number.
- Password reset (assumption): email users reset by email link; phone-only users are reset by HR or Admin. Every reset is audit-logged. Nobody can see anyone's password.
- Repeated wrong passwords lock the account for a period. The error message is always the same ("ID or password is wrong").
- Revoking portal access or deactivating an employee disables the login immediately.
- The login token carries the user's org and role. Organization is taken from the active employment.

### 2.5 Row-level security policy

- Company isolation: a user can only read or write rows whose org\_id matches their own organization. This is the most important test.
- Role checks: every action requires a permission from the user's role.
- Employee role: sees and edits only their own profile.
- Manager role: sees the whole company's people list, limited to the fields the Admin allowed for that role.
- HR Manager role: manages employees and org structure inside their company, limited by role permissions.
- Admin/Owner: full access inside their own company only, never another company.
- Sensitive fields (NID now; salary and bank later) live in separate tables and are readable only by roles the Admin ticked.
- Roles can be created, edited or assigned only by Admin/Owner. An Admin cannot remove their own admin access. Role changes are audit-logged.
- The service key is used only on the server, never in the browser.

### 2.6 Server operations

1. Create organization (generates org code and default roles and grades).
2. Create employee: employee row, card ID, history row "joined", optional reporting lines, audit row, all in one transaction.
3. Assign and revoke portal access.
4. Transfer employee (office, branch, department) and promote (designation, grade): writes a history row and an audit row.
5. Change reporting manager: closes the old line, opens the new one.
6. Deactivate department, designation, branch or office, with the target-branch transfer flow for branch and office.
7. Create, edit and assign roles; save field visibility.
8. Reset a user's password (HR/Admin).

### 2.7 Validation rules

- Full name required (as per NID card). Phone format 01XXXXXXXXX or +880…, NID 10, 13 or 17 digits.
- An inactive department, designation, branch or office cannot receive a new employee.
- A designation belongs to exactly one department.
- Duplicate card ID inside an organization is rejected.
- Duplicate email or phone anywhere in the system is rejected.

## 3. UI

Style follows the spec: orange primary, rounded cards, Tailwind, React Query for server data, Zustand for login and organization state. Every page needs loading, empty and error states. Buttons the user may not use are hidden, and the database still blocks them.

| Area | Screens |
| --- | --- |
| Login | One page, one field for email or mobile, password. First-login forced password change. |
| Organization | Tabs for Departments, Designations, Grades, Branches, Offices, Operations. Each has a table, Add form, Edit, and Active/Inactive toggle. |
| Branch/office deactivate | Dialog asking for the target branch, showing how many employees will move. |
| Employees list | KPI tiles (Total, Active, Portal Access, Departments), table, search, filters (status, department, branch, employment type). |
| Add Employee | Step 1: personal info, identification and job, nominee, address. Step 2: role, employment type, card ID, reporting chain. Create. |
| Employee profile | Header with avatar and status. Tabs: Personal Info, History, Reporting Chain. Edit, Deactivate, Assign/Revoke Portal Access. |
| Settings: Roles | Role list, create role, permission checkboxes, per-field view/edit checkboxes. |
| Settings: Card ID policy | Auto or custom, length 8–10. |
| Audit log | Admin-only table with filters by user, action, date. Read-only. |

## 4. Policies

- **Tenancy:** no data ever crosses organizations.
- **Access:** least privilege. Permissions come from the role, never from the grade.
- **Identity:** UUID for links, card ID for cards only, org code never changes.
- **Passwords:** company-issued first password, forced change, lockout after repeated failures, no password visible to staff.
- **Soft delete:** nothing is physically removed. Inactive or terminated stays in history.
- **History:** every transfer, promotion and reporting change is recorded with effective date and reason.
- **Audit:** who, when, which company, old value and new value. Append-only. Minimum 3 years retention. Only the system may purge records older than 3 years, never a person. Check any longer legal retention rule before payroll arrives.
- **Sensitive data:** NID and later salary and bank are shown only to roles that were ticked by the Admin.
- **Deactivation:** a branch or office cannot go inactive until employees have a target.
- **Transfer between companies:** a new employment with a new card ID. The old company's data stays hidden from the new one.

## 5. Total feature list for Part 1

**Backend**

- Organization with random 6-digit org code
- Email or phone login with password policy and forced first change
- Roles, permissions and per-field visibility
- Row-level security on every table
- Departments, designations, grades, branches, offices, operations
- Employees, nominees, sensitive-data table
- Card ID generation and custom ID policy
- Employment history and reporting-chain history
- Portal access assign and revoke
- Branch and office deactivation with transfer
- Append-only audit log with 3-year retention

**UI**

- Login and first-login password change
- Organization tabs with add, edit, toggle
- Employees list with KPIs, search and filters
- 2-step Add Employee and Edit
- Employee profile with Personal Info, History and Reporting Chain
- Portal Access dialog
- Roles and field-visibility settings
- Card ID policy settings
- Audit log viewer

**Policy**

- All rules in Section 4 enforced and tested

## 6. Acceptance tests

Use two companies and these users: an Owner/Admin, an HR Manager, a Manager (MS), and employees EM0, EM1, EM2, EM3, EM4. Test by hand.

1. Company A's admin cannot see, edit or fetch any Company B data through screen or API.
2. Inside one company, each role sees only what its permissions and field ticks allow. An Employee sees only themselves.
3. A Manager sees the whole people list but not sensitive fields unless ticked.
4. Departments, designations, branches and offices can be created, edited and made inactive. A designation is tied to its department.
5. Adding an employee creates a card ID that is unique in the organization. Two employees added at the same time get different IDs. A duplicate custom ID is rejected.
6. Email login works. Phone login works. A duplicate phone or email is rejected.
7. Portal access assigned works, revoked stops working immediately.
8. An inactive department or branch cannot receive a new employee.
9. Deactivating a branch moves its employees to the chosen branch and writes history and audit rows.
10. Changing a reporting manager keeps the old record.
11. Audit rows cannot be edited or deleted, even by Admin.
12. A role cannot be created or changed by a non-Admin, and an Admin cannot remove their own admin access.

## 7. What "done" means

All Section 6 tests pass, the feature list in Section 5 is complete, and the code is committed and tagged as the Part 1 release. Then Part 2 starts.

## 8. Build order inside Part 1

Each step: build, test by hand, commit, then continue.

1. Foundation: organizations, user profiles, roles and permissions, row-level security, audit log. Test company isolation first.
2. Login: email and phone, first-login password change, lockout.
3. Organization structure: grades, departments, designations, branches, offices, operations.
4. Roles screen and field visibility.
5. Employees: create, list, filters, edit, deactivate, card ID generation.
6. History, reporting chain and nominees.
7. Portal access assign and revoke.
8. Deactivation flows with target-branch transfer.
9. Audit log viewer and full acceptance test pass.

## 9. Assumptions to confirm

1. Departments are organization-wide, not per branch.
2. Password reset for phone-only users is done by HR or Admin. SMS OTP can be added later.
3. Auto card ID is the joining year plus random digits, total length 8–10 chosen by the organization.
4. MS grades are MS0–MS2. The list is data, so it can grow.
5. Each user has exactly one role at a time.
6. An employee can exist before a login is assigned.
7. Employee religion and blood group stay as in the spec but may be hidden by role.
8. SMS provider for number verification is not decided; verification is optional in Part 1.
