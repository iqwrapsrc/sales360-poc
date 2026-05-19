/**
 * Verifies that the Phase 4-5 Data Cloud artifacts exist and are queryable.
 * Tests both DMO SOQL access and CIO ConnectApi.CdpQuery access.
 *
 * Run via: sf apex run --file scripts/apex/verify-data-cloud.apex --target-org sales360-dev
 */

System.debug('=== Verifying Data Cloud Artifacts ===');

// Test 1: DMO SOQL access (Agency master DMO)
System.debug('Test 1: Agency__dlm SOQL query...');
try {
    Integer agencyCount = Database.countQuery('SELECT COUNT() FROM Agency__dlm');
    System.debug('[OK] Agency__dlm contains ' + agencyCount + ' records');
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR,
        '[FAIL] Agency__dlm query failed: ' + e.getMessage());
}

// Test 2: OD Pair DMO SOQL access
System.debug('Test 2: OD_Pair__dlm SOQL query...');
try {
    Integer odPairCount = Database.countQuery('SELECT COUNT() FROM OD_Pair__dlm');
    System.debug('[OK] OD_Pair__dlm contains ' + odPairCount + ' records');
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR,
        '[FAIL] OD_Pair__dlm query failed: ' + e.getMessage());
}

// Test 3: CIO via ConnectApi.CdpQuery
System.debug('Test 3: Flown_Revenue_By_Agency__cio CdpQuery...');
try {
    ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
    input.sql = 'SELECT COUNT(*) AS rowCount FROM Flown_Revenue_By_Agency__cio';
    ConnectApi.CdpQueryOutput output = ConnectApi.CdpQuery.queryAnsiSql(input);
    if (output != null && output.data != null && !output.data.isEmpty()) {
        Map<String, Object> row = (Map<String, Object>) output.data[0];
        System.debug('[OK] Flown_Revenue_By_Agency__cio contains ' + row.get('rowCount') + ' rows');
    } else {
        System.debug(LoggingLevel.ERROR, '[FAIL] Empty response from CdpQuery');
    }
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR,
        '[FAIL] Flown_Revenue_By_Agency__cio CdpQuery failed: ' + e.getMessage());
}

// Test 4: Sample portfolio data fetch end-to-end
System.debug('Test 4: End-to-end portfolio data fetch...');
try {
    List<Map<String, Object>> portfolioData =
        Sales360DataService.getAgencyPortfolioData('USER_001', 'FY26Q1');
    System.debug('[OK] getAgencyPortfolioData returned ' + portfolioData.size() + ' agencies');
    if (!portfolioData.isEmpty()) {
        System.debug('Sample agency: ' + JSON.serializePretty(portfolioData[0]));
    }
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR,
        '[FAIL] End-to-end fetch failed: ' + e.getMessage());
}

System.debug('=== Verification Complete ===');
System.debug('Review the [OK] / [FAIL] markers above.');
System.debug('If FAIL: verify field names in Sales360DataService.cls match your DMO schema.');
