/**
 * Verifies that the Phase 6 Prompt Templates (PT1 + PT2) exist and are active.
 *
 * Run via: sf apex run --file scripts/apex/verify-phase6-artifacts.apex --target-org sales360-dev
 */

System.debug('=== Verifying Phase 6 Prompt Templates ===');

List<String> requiredTemplates = new List<String>{
    'Portfolio_Summary_JSON_Template',
    'Opportunity_Spotlight_JSON_Template'
};

Map<String, Boolean> verified = new Map<String, Boolean>();
for (String t : requiredTemplates) verified.put(t, false);

// Query Prompt Templates via tooling/metadata
// Note: Direct metadata query for GenAiPromptTemplate requires Tooling API
// We'll do a smoke test by attempting to invoke each template with a minimal input

for (String templateName : requiredTemplates) {
    try {
        // Attempt minimal invocation to verify template exists
        Map<String, String> testInputs = new Map<String, String>{
            'userId' => 'USER_001',
            'fiscalPeriod' => 'FY26Q1',
            'agencyDataJson' => '[]',
            'odPairDataJson' => '[]'
        };

        // Only call PromptTemplateInvoker if we have it
        // (Will fail if template doesn't exist OR if Einstein not enabled - both indicate problem)
        String response = PromptTemplateInvoker.invoke(templateName, testInputs);
        if (String.isNotBlank(response)) {
            verified.put(templateName, true);
            System.debug('VERIFIED: ' + templateName + ' is accessible');
            System.debug('Response preview: ' + response.left(100) + '...');
        }
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'FAIL: ' + templateName + ' - ' + e.getMessage());
    }
}

System.debug('=== Verification Summary ===');
Boolean allOk = true;
for (String t : verified.keySet()) {
    Boolean ok = verified.get(t);
    System.debug((ok ? '[OK]   ' : '[FAIL] ') + t);
    if (!ok) allOk = false;
}

if (allOk) {
    System.debug('SUCCESS: All Phase 6 Prompt Templates are accessible');
} else {
    System.debug(LoggingLevel.ERROR,
        'One or more Phase 6 templates are missing or inaccessible.');
    System.debug('Possible causes:');
    System.debug('  1. Phase 6 templates were not built in this org');
    System.debug('  2. Einstein Generative AI User permission set not assigned to running user');
    System.debug('  3. Template is not in Active status');
}
