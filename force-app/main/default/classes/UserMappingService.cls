/**
 * @description  Maps Salesforce User IDs to demo persona owner IDs.
 *               Reads from Test_User_Mapping__c custom setting.
 *               Used by all three Sales360 controllers to resolve which test data owner
 *               the current SF user should see.
 *
 * @author       Anup Chandran (Emirates Group IT)
 * @phase        Sales360 PoC - Phase 7
 * @since        May 2026
 * @updated      May 2026 - Persona selector now displays the raw owner ID (USER_001 etc.)
 *                          instead of the friendly label, and returns personas sorted by ID.
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
     * Label and value are both the owner ID (USER_001, USER_002, ...), sorted ascending.
     *
     * @return List of maps with 'value' and 'label' both = Mapped_Owner_Id__c
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAvailablePersonas() {
        // Collect distinct owner IDs
        Set<String> ownerIds = new Set<String>();
        for (Test_User_Mapping__c m : Test_User_Mapping__c.getAll().values()) {
            if (String.isNotBlank(m.Mapped_Owner_Id__c)) {
                ownerIds.add(m.Mapped_Owner_Id__c);
            }
        }

        // Sort so the dropdown reads USER_001, USER_002, USER_003 ...
        List<String> sortedIds = new List<String>(ownerIds);
        sortedIds.sort();

        List<Map<String, String>> personas = new List<Map<String, String>>();
        for (String ownerId : sortedIds) {
            personas.add(new Map<String, String>{
                'value' => ownerId,
                'label' => ownerId
            });
        }
        return personas;
    }
}
