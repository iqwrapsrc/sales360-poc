# Sales360 PoC — Phase 7 SFDX Project

This is the **deployable SFDX project** for Phase 7 of the Sales360 PoC. It contains every Apex class, LWC, custom object, custom setting, app page, and permission set needed to deploy the Sales360 Unified Desktop to a Salesforce org.

**Last updated:** May 2026
**Phase:** 7 of 8
**API Version:** 62.0

---

## Quick start

```bash
# 1. Authenticate to your org (one time)
sf org login web --alias sales360-dev --instance-url https://login.salesforce.com

# 2. Deploy everything
sf project deploy start --source-dir force-app --target-org sales360-dev

# 3. Run the post-deploy data seeding
sf apex run --file scripts/apex/seed-user-mapping.apex --target-org sales360-dev

# 4. Assign permission set to your user
sf org assign permset --name Sales360_Performance_User --target-org sales360-dev

# 5. Open the org and navigate to Sales360 Unified Desktop
sf org open --target-org sales360-dev --path lightning/n/Sales360_Unified_Desktop
```

---

## What this project deploys

### Custom Objects (1)
- `EK_Sales360_Cache__c` — Two-layer cache storage with 12 fields

### Custom Settings (1)
- `Test_User_Mapping__c` — List custom setting mapping SF user → demo persona

### Apex Classes (8)
- `PromptTemplateInvoker` — ConnectApi.EinsteinLLM wrapper
- `UserMappingService` — User to demo persona resolution
- `Sales360CacheService` — L1 (Platform Cache) + L2 (Custom Object) cache
- `Sales360DataService` — DMO SOQL + CIO CdpQuery orchestration
- `KpiAggregationService` — Deterministic CI aggregation for KPI bar (no LLM)
- `Sales360KpiController` — LWC entry for My Performance KPI Bar
- `Sales360PortfolioController` — LWC entry for Portfolio Summary
- `Sales360SpotlightController` — LWC entry for Opportunity Spotlight

### Lightning Web Components (5)
- `myPerformanceKpiBar` — Top-of-page KPI strip (Required)
- `periodFilterPicker` — Fiscal period dropdown (Required)
- `portfolioSummaryPanel` — Portfolio Summary AI panel (Required)
- `opportunitySpotlightPanel` — AI Opportunity Spotlight panel (Required)
- `demoPersonaSelector` — Demo persona switcher (Optional)

### Lightning App Page (1)
- `Sales360_Unified_Desktop` — FlexiPage hosting all LWCs

### Custom Tab (1)
- `Sales360_Unified_Desktop` — Tab providing navigation access

### Custom Application (1)
- `Sales360_App` — App container exposing the desktop tab

### Permission Set (1)
- `Sales360_Performance_User` — Grants read access to all Phase 7 artifacts

### Custom Labels (5)
- Brand colors, headings, and other localizable strings

---

## What MUST be done manually (cannot be deployed via SFDX)

These artifacts require Setup UI configuration. Run AFTER the SFDX deploy.

### 1. Platform Cache Partition (REQUIRED)

**Why manual:** Platform Cache partitions cannot be deployed via metadata API.

**Steps:**
1. Setup → Quick Find: "Platform Cache"
2. Click **New Platform Cache Partition**
3. Configure:
   - Label: `Sales360`
   - Name: `Sales360`
   - Description: `L1 cache for Sales360 PoC`
   - **Org Cache:** 1 MB (recommended)
   - **Session Cache:** 0 MB (not used)
4. Mark as **Default Partition** if you want it auto-selected (optional)
5. Click Save

**Verification:**
```bash
sf apex run --file scripts/apex/verify-platform-cache.apex --target-org sales360-dev
```

### 2. Einstein Generative AI Permission (REQUIRED)

**Why manual:** Permission set assignments need to be verified per-user.

**Steps:**
1. Setup → Users → Find your user (e.g., Hanu Pocs)
2. Permission Set Assignments → Edit Assignments
3. Add the following permission sets if not already assigned:
   - **Einstein Generative AI User** (provides access to Einstein Prompt Templates)
   - **Data Cloud Admin** or **Data Cloud User** (provides access to DMOs and CIOs)
4. Save

### 3. Verify Phase 6 artifacts exist (REQUIRED)

These were built in Phase 6 and are NOT included in this project (since they already exist in your org):

**Phase 6 artifacts to verify:**
- Prompt Templates:
  - `Portfolio_Summary_JSON_Template` (status: Active)
  - `Opportunity_Spotlight_JSON_Template` (status: Active)

**Verification command:**
```bash
sf apex run --file scripts/apex/verify-phase6-artifacts.apex --target-org sales360-dev
```

### 4. Verify Phase 4-5 Data Cloud artifacts exist (REQUIRED)

These were built in Phase 4-5 and must exist:
- DMOs: `Agency__dlm`, `OD_Pair__dlm`, `Agency_Performance__dlm`, `Route_Market__dlm`, `Target__dlm`
- Calculated Insights: 8 CIs including `Flown_Revenue_By_Agency__cio`, `Flown_PAX_By_Agency__cio`, etc.

**Verification command:**
```bash
sf apex run --file scripts/apex/verify-data-cloud.apex --target-org sales360-dev
```

### 5. Seed Test_User_Mapping__c records (REQUIRED after first deploy)

Custom Setting records are DATA not METADATA, so deploy via Apex script.

**Steps:**
1. Edit `scripts/apex/seed-user-mapping.apex` and replace the user IDs with your actual SF user ID (run `sf org display user` to get yours)
2. Run:
```bash
sf apex run --file scripts/apex/seed-user-mapping.apex --target-org sales360-dev
```

### 6. Add the Sales360 Unified Desktop App to App Launcher (OPTIONAL)

**Why manual:** App visibility per profile is often configured live, not deployed.

**Steps:**
1. Setup → App Manager → Sales360 App → Edit
2. Under "Available in Lightning Experience", set User Profiles allowed
3. Save

---

## Deployment commands reference

### Deploy entire project
```bash
sf project deploy start --source-dir force-app --target-org sales360-dev
```

### Deploy specific component
```bash
# Just Apex classes
sf project deploy start --source-dir force-app/main/default/classes --target-org sales360-dev

# Just LWCs
sf project deploy start --source-dir force-app/main/default/lwc --target-org sales360-dev

# Single LWC
sf project deploy start --source-dir force-app/main/default/lwc/myPerformanceKpiBar --target-org sales360-dev
```

### Deploy via manifest (preferred for production)
```bash
sf project deploy start --manifest manifest/package.xml --target-org sales360-dev
```

### Validate deployment without committing
```bash
sf project deploy start --source-dir force-app --target-org sales360-dev --dry-run
```

### Run tests during deploy
```bash
sf project deploy start --source-dir force-app --target-org sales360-dev --test-level RunLocalTests
```

### Retrieve changes from org back to project
```bash
sf project retrieve start --manifest manifest/package.xml --target-org sales360-dev
```

### Delete artifacts from org (destructive)
```bash
sf project deploy start --manifest manifest/destructive.xml --post-destructive-changes manifest/destructive.xml --target-org sales360-dev
```

---

## Build sequence (recommended order)

If you want to build incrementally, follow this order matching Phase 7 v1.1 design Section 8:

```bash
# Step 1-3: Foundation (custom object + custom setting + platform cache)
sf project deploy start --source-dir force-app/main/default/objects --target-org sales360-dev
# Then manually create Platform Cache partition

# Step 4-10: Apex classes
sf project deploy start --source-dir force-app/main/default/classes --target-org sales360-dev

# Step 11: Period Filter LWC
sf project deploy start --source-dir force-app/main/default/lwc/periodFilterPicker --target-org sales360-dev

# Step 12: My Performance KPI Bar LWC
sf project deploy start --source-dir force-app/main/default/lwc/myPerformanceKpiBar --target-org sales360-dev

# Step 13: Portfolio Summary Panel LWC
sf project deploy start --source-dir force-app/main/default/lwc/portfolioSummaryPanel --target-org sales360-dev

# Step 14-15: (Apex already deployed in step 4-10)

# Step 16: Opportunity Spotlight Panel LWC
sf project deploy start --source-dir force-app/main/default/lwc/opportunitySpotlightPanel --target-org sales360-dev

# Step 17: Sales360 Unified Desktop App Page
sf project deploy start --source-dir force-app/main/default/flexipages --target-org sales360-dev
sf project deploy start --source-dir force-app/main/default/tabs --target-org sales360-dev
sf project deploy start --source-dir force-app/main/default/applications --target-org sales360-dev

# Step 18: Demo Persona Selector (optional)
sf project deploy start --source-dir force-app/main/default/lwc/demoPersonaSelector --target-org sales360-dev

# Step 19: Permission Set
sf project deploy start --source-dir force-app/main/default/permissionsets --target-org sales360-dev
sf org assign permset --name Sales360_Performance_User --target-org sales360-dev
```

---

## Project structure

```
sales360-sfdx/
├── README.md                          (this file)
├── sfdx-project.json                  (SFDX configuration)
├── .gitignore
├── .forceignore
├── force-app/
│   └── main/
│       └── default/
│           ├── objects/
│           │   ├── EK_Sales360_Cache__c/      (custom object + 12 fields)
│           │   └── Test_User_Mapping__c/       (custom setting + 5 fields)
│           ├── classes/                         (8 Apex classes + meta-xml)
│           ├── lwc/
│           │   ├── myPerformanceKpiBar/        (JS, HTML, CSS, meta)
│           │   ├── periodFilterPicker/
│           │   ├── portfolioSummaryPanel/
│           │   ├── opportunitySpotlightPanel/
│           │   └── demoPersonaSelector/
│           ├── flexipages/                      (Sales360 Unified Desktop)
│           ├── tabs/                            (Sales360 Unified Desktop tab)
│           ├── applications/                    (Sales360 App)
│           ├── permissionsets/                  (Sales360_Performance_User)
│           └── labels/                          (Custom labels)
├── manifest/
│   ├── package.xml                              (deployment manifest)
│   └── destructive.xml                          (for rollback)
├── scripts/
│   └── apex/
│       ├── seed-user-mapping.apex               (post-deploy data seeding)
│       ├── verify-platform-cache.apex
│       ├── verify-phase6-artifacts.apex
│       └── verify-data-cloud.apex
├── data/                                         (sample data for tests)
└── config/
    └── project-scratch-def.json                  (optional: scratch org config)
```

---

## Troubleshooting

### Issue: "Field 'agency_id__c' not found on Agency__dlm"

**Cause:** Phase 4 DMO field names in your org may differ from what's coded.

**Fix:**
```bash
# Verify actual field names on your DMO
sf data query --query "SELECT QualifiedApiName, DataType FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = 'Agency__dlm'" --target-org sales360-dev
```

Then update the SOQL in `Sales360DataService` to use the actual field API names.

### Issue: "Method does not exist or incorrect signature: ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate"

**Cause:** Apex API version may not support EinsteinLLM in your org.

**Fix:** Verify with:
```apex
System.debug(ConnectApi.EinsteinLLM.class.getName());
```

### Issue: LWC deploys but doesn't render in App Page

**Cause:** LWC's `meta.xml` may not expose it to App Page targets.

**Fix:** Verify the `meta.xml` includes `lightning__AppPage` in the `<targets>` list. All LWCs in this project are already configured correctly.

### Issue: "Insufficient privileges" when running LWC

**Cause:** User missing Einstein Generative AI permission set.

**Fix:** Assign the Einstein Generative AI User permission set (see manual steps section #2).

---

## Phase 7 → Phase 8 evolution

Phase 8 will add conversational chat capability. The Apex services and Custom Object designed in Phase 7 are reusable for Phase 8 — only new LWCs (chat interface) and new Apex methods are added.

When Phase 8 is built, expect the following additions to this SFDX project:
- New LWC: `salesAdvisorChat`
- New Apex class: `Sales360ChatController`
- New Apex class: `Sales360ConversationService`
- New picklist value for `EK_Sales360_Cache__c.Response_Type__c`: `CHAT_RESPONSE`
- (Possibly) new Prompt Templates for conversational responses

---

## Support

For issues with this project structure, refer to:
- **Phase 7 v1.1 Design Document:** `EK-SALES360-POC-PHASE-7-Apex-LWC-Build-v1.1.docx`
- **Phase 6 v1.3 Closure Document:** `EK-SALES360-POC-PHASE-6-Agentforce-Build-v1.3.docx`

---

## Author

**Anup Chandran** — Sr. Salesforce CRM Solutions Architect — Emirates Group IT
