# Sales360 Phase 7 SFDX Project - Manifest of Deliverables

## Project root files (4)
- sfdx-project.json
- .gitignore
- .forceignore
- README.md

## Custom Objects (2 + 16 fields)
### EK_Sales360_Cache__c (Phase 7 cache storage)
- Object definition with 'Cache Key' as nameField
- 11 custom fields:
  - User_Id__c (Text 40, External ID, Required)
  - Fiscal_Period__c (Text 10, Required)
  - Response_Type__c (Picklist: MY_PERFORMANCE_KPI, PORTFOLIO_SUMMARY, OPPORTUNITY_SPOTLIGHT)
  - Schema_Version__c (Text 10, default "1.0")
  - JSON_Payload__c (LongText 131072)
  - Generated_At__c (DateTime)
  - Expires_At__c (DateTime)
  - Hit_Count__c (Number, default 0)
  - Generation_Source__c (Picklist: APEX_FRESH, APEX_REFRESHED, MANUAL_REFRESH)
  - Generation_Time_Ms__c (Number)
  - Is_Stale__c (Checkbox, default false)

### Test_User_Mapping__c (Custom Setting List)
- 4 custom fields:
  - Mapped_Owner_Id__c (Text 20, Required)
  - Demo_Persona_Label__c (Text 60)
  - Is_Default__c (Checkbox)
  - Description__c (Text 255)

## Apex Classes (8 classes + 8 meta-xml)
- PromptTemplateInvoker.cls          (62 lines - ConnectApi.EinsteinLLM wrapper)
- UserMappingService.cls              (74 lines - User to persona resolution)
- Sales360CacheService.cls            (186 lines - L1+L2 cache with TTL override)
- Sales360DataService.cls             (170 lines - DMO SOQL + CIO CdpQuery)
- KpiAggregationService.cls           (220 lines - Deterministic KPI aggregation)
- Sales360KpiController.cls           (122 lines - KPI Bar AuraEnabled entry)
- Sales360PortfolioController.cls     (153 lines - Portfolio AuraEnabled entry)
- Sales360SpotlightController.cls     (138 lines - Spotlight AuraEnabled entry)

## Lightning Web Components (5 components)
- periodFilterPicker         (JS + HTML + CSS + meta-xml)
- myPerformanceKpiBar        (JS + HTML + CSS + meta-xml) - KPI Bar with Emirates branding
- portfolioSummaryPanel      (JS + HTML + CSS + meta-xml) - AI Portfolio panel
- opportunitySpotlightPanel  (JS + HTML + CSS + meta-xml) - AI Spotlight panel
- demoPersonaSelector        (JS + HTML + CSS + meta-xml) - Optional persona switcher

## Lightning App Page (1)
- Sales360_Unified_Desktop (FlexiPage with 4 regions: top, kpiBar, left, right)

## Custom Tab (1)
- Sales360_Unified_Desktop tab

## Custom Application (1)
- Sales360_App (Lightning navType, navy header color)

## Permission Set (1)
- Sales360_Performance_User (grants object + field + class + tab + app access)

## Apex Helper Scripts (4)
- scripts/apex/seed-user-mapping.apex         (POST-DEPLOY: edit user ID, then run)
- scripts/apex/verify-platform-cache.apex     (Verifies Platform Cache partition)
- scripts/apex/verify-phase6-artifacts.apex   (Verifies PT1/PT2 exist)
- scripts/apex/verify-data-cloud.apex         (Verifies DMO + CIO access)

## Manifest Files (2)
- manifest/package.xml          (Full deployment manifest)
- manifest/destructive.xml      (Rollback manifest)

## Config (1)
- config/project-scratch-def.json (Optional - for scratch org definition)

## Total Files: 68

## Deployment Order
1. Manual: Create Platform Cache partition 'Sales360' (UI, 1 MB org cache)
2. SFDX:   Deploy force-app folder
3. Apex:   Run seed-user-mapping.apex (after editing user ID)
4. SFDX:   Assign Sales360_Performance_User permission set to user
5. Manual: Assign Einstein Generative AI User permission set to user
6. Manual: Open Sales360 Unified Desktop tab in Lightning UI
