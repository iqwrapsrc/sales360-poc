/**
 * Verifies that the 'Sales360' Platform Cache partition has been created.
 *
 * If this script fails, follow the manual step in README.md:
 *   Setup -> Platform Cache -> New Platform Cache Partition
 *   Label: Sales360, Name: Sales360, Org Cache: 1 MB
 *
 * Run via: sf apex run --file scripts/apex/verify-platform-cache.apex --target-org sales360-dev
 */

try {
    Cache.OrgPartition partition = Cache.Org.getPartition('local.Sales360');
    if (partition == null) {
        System.debug(LoggingLevel.ERROR,
            'FAIL: Platform Cache partition local.Sales360 not found.');
        System.debug('Action required: Setup -> Platform Cache -> create partition named Sales360');
        return;
    }

    // Test put + get cycle
    String testKey = 'test_key_' + Datetime.now().getTime();
    String testValue = 'test_value_' + Datetime.now().format();
    partition.put(testKey, testValue, 60);

    Object retrieved = partition.get(testKey);
    if (retrieved != null && testValue.equals((String) retrieved)) {
        System.debug('SUCCESS: Platform Cache partition local.Sales360 is working');
        System.debug('Test write/read cycle completed in milliseconds');
    } else {
        System.debug(LoggingLevel.ERROR,
            'FAIL: Platform Cache write/read cycle did not return expected value');
    }

    // Cleanup
    partition.remove(testKey);

} catch (Exception e) {
    System.debug(LoggingLevel.ERROR, 'FAIL: ' + e.getMessage());
    System.debug('Most common cause: Platform Cache partition Sales360 has not been created');
    System.debug('See README.md section "Manual Steps - Platform Cache Partition" for instructions');
}
