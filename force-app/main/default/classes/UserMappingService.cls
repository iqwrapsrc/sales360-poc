/**
 * @description  Maps Salesforce User IDs to demo persona owner IDs.
 *               Reads from Test_User_Mapping__c custom setting.
 *               Used by all three Sales360 controllers to resolve which test data owner
 *               the current SF user should see.
 *
 * @author       Anup Chandran (Emirates Group IT)
 * @phase        Sales360 PoC - Phase 7
 * @since        May 2026
 */
public with sharing class UserMappingService {

    @TestVisible
    private static final String DEFAULT_OWNER_ID = 'USER_001';

    /**
     * Resolves a Salesforce User ID to a test data owner ID.
     * If overridePersona is provided (e.g., from Demo Persona Selector), it takes precedence.
     * Otherwise, looks up Custom Setting. Falls back to DEFAULT_OWNER_ID.
     *
     * @param salesforceUserId  The currently-running SF user ID (typically UserInfo.getUserId())
     * @param overridePersona   Optional persona override from the LWC (e.g., 'USER_002')
     * @return                  The resolved test data owner ID
     */
    public static String resolveOwnerId(String salesforceUserId,
                                         String overridePersona) {
        // Override always wins (used by Demo Persona Selector)
        if (String.isNotBlank(overridePersona)) {
            return overridePersona;
        }

        // Lookup Custom Setting
        Test_User_Mapping__c mapping =
            Test_User_Mapping__c.getInstance(salesforceUserId);
        if (mapping != null && String.isNotBlank(mapping.Mapped_Owner_Id__c)) {
            return mapping.Mapped_Owner_Id__c;
        }

        // Lookup the explicit default record
        Map<String, Test_User_Mapping__c> all = Test_User_Mapping__c.getAll();
        for (Test_User_Mapping__c m : all.values()) {
            if (m.Is_Default__c && String.isNotBlank(m.Mapped_Owner_Id__c)) {
                return m.Mapped_Owner_Id__c;
            }
        }

        // Fall back to hardcoded default
        return DEFAULT_OWNER_ID;
    }

    /**
     * Returns all available demo personas for the Demo Persona Selector LWC.
     *
     * @return List of maps with 'value' (Mapped_Owner_Id__c) and 'label' (Demo_Persona_Label__c)
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAvailablePersonas() {
        List<Map<String, String>> personas = new List<Map<String, String>>();
        Map<String, Test_User_Mapping__c> all = Test_User_Mapping__c.getAll();
        for (Test_User_Mapping__c m : all.values()) {
            personas.add(new Map<String, String>{
                'value' => m.Mapped_Owner_Id__c,
                'label' => String.isNotBlank(m.Demo_Persona_Label__c) ?
                            m.Demo_Persona_Label__c : m.Mapped_Owner_Id__c
            });
        }
        return personas;
    }
}
