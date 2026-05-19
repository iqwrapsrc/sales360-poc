/**
 * Seeds Test_User_Mapping__c custom setting records for the Sales360 PoC demo.
 *
 * BEFORE RUNNING:
 * 1. Get your Salesforce User ID by running:
 *    sf org display user --target-org sales360-dev
 * 2. Replace the placeholder ID below with your actual user ID
 * 3. Run via: sf apex run --file scripts/apex/seed-user-mapping.apex --target-org sales360-dev
 */

// === EDIT THIS LINE: Replace with your actual SF user ID (Id starts with 005) ===
String myUserId = '005g5000006DGJdAAO';

// Validate
if (!myUserId.startsWith('005') || myUserId.contains('XXX')) {
    System.debug(LoggingLevel.ERROR,
        'ERROR: Replace myUserId with your real SF user ID before running.');
    return;
}

// Delete any existing mappings (idempotent)
delete [SELECT Id FROM Test_User_Mapping__c];

// Insert 3 personas for demo
List<Test_User_Mapping__c> mappings = new List<Test_User_Mapping__c>{

    // Default mapping for the current SF user (uses SF user ID as the Name)
    new Test_User_Mapping__c(
        Name = myUserId,
        Mapped_Owner_Id__c = 'USER_001',
        Demo_Persona_Label__c = 'India Sales Lead',
        Is_Default__c = true,
        Description__c = 'Default persona - India-focused sales executive owning 20 agencies'
    ),

    // Alternative persona - UAE
    new Test_User_Mapping__c(
        Name = 'PERSONA_UAE',
        Mapped_Owner_Id__c = 'USER_002',
        Demo_Persona_Label__c = 'UAE Senior AE',
        Is_Default__c = false,
        Description__c = 'UAE-focused sales executive'
    ),

    // Alternative persona - South Asia
    new Test_User_Mapping__c(
        Name = 'PERSONA_SASIA',
        Mapped_Owner_Id__c = 'USER_003',
        Demo_Persona_Label__c = 'South Asia Manager',
        Is_Default__c = false,
        Description__c = 'South Asia regional manager'
    )
};

insert mappings;

System.debug('=== Seeded ' + mappings.size() + ' Test_User_Mapping__c records ===');
for (Test_User_Mapping__c m : [SELECT Name, Mapped_Owner_Id__c, Demo_Persona_Label__c,
                                       Is_Default__c FROM Test_User_Mapping__c]) {
    System.debug(m.Demo_Persona_Label__c + ' (' + m.Mapped_Owner_Id__c + ')'
                 + (m.Is_Default__c ? ' [DEFAULT]' : ''));
}

// Verify UserMappingService now resolves correctly
String resolved = UserMappingService.resolveOwnerId(myUserId, null);
System.debug('UserMappingService.resolveOwnerId(' + myUserId + ', null) = ' + resolved);
System.assertEquals('USER_001', resolved, 'Default mapping should resolve to USER_001');
System.debug('=== SUCCESS: User mappings seeded correctly ===');
