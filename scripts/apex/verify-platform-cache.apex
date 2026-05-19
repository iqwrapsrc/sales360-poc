/**
 * Verifies that the 'Sales360' Platform Cache partition has been created.
 *
 * If this script fails, follow the manual step in README.md:
 *   Setup -> Platform Cache -> New Platform Cache Partition
 *   Label: Sales360, Name: Sales360, Org Cache: 1 MB (Provider Free is fine)
 *
 * Run via: sf apex run --file scripts/apex/verify-platform-cache.apex --target-org sales360-dev
 *
 * NOTE: Platform Cache has two important restrictions:
 *   1. Keys must be alphanumeric only (no underscores, pipes, or special chars)
 *   2. Org Cache minimum TTL is 300 seconds
 */

try {
    Cache.OrgPartition partition = Cache.Org.getPartition('local.Sales360');
    if (partition == null) {
        System.debug(LoggingLevel.ERROR,
            'FAIL: Platform Cache partition local.Sales360 not found.');
        System.debug('Action required: Setup -> Platform Cache -> create partition named Sales360');
        return;
    }

    // Test put + get cycle with alphanumeric key and minimum TTL
    String testKey = 'testkey' + String.valueOf(Datetime.now().getTime());
    String testValue = 'testvalue';
    partition.put(testKey, testValue, 300);

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
    System.debug('Most common causes:');
    System.debug('  1. Platform Cache partition Sales360 has not been created');
    System.debug('  2. Cache key contains non-alphanumeric characters');
    System.debug('  3. Cache TTL below 300 second minimum');
    System.debug('See README.md section "Manual Steps - Platform Cache Partition" for instructions');
}
