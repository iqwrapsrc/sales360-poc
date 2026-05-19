/**
 * @description  Two-layer cache service for Sales360 AI responses.
 *               L1: Platform Cache (org partition 'Sales360') - sub-second access
 *               L2: EK_Sales360_Cache__c custom object - persistent across app server restarts
 *
 *               L1 key format: alphanumeric only (Platform Cache restriction)
 *               L2 key format: userId|fiscalPeriod|responseType (human-readable, stored in Name)
 *
 *               Different response types can have different TTL values.
 *
 * @author       Anup Chandran (Emirates Group IT)
 * @phase        Sales360 PoC - Phase 7
 * @since        May 2026
 * @updated      May 2026 - Fixed L1 key to satisfy Platform Cache alphanumeric restriction
 */
public with sharing class Sales360CacheService {

    @TestVisible
    private static final Integer DEFAULT_TTL_HOURS = 24;

    @TestVisible
    private static final Integer KPI_TTL_HOURS = 6;

    @TestVisible
    private static final String CACHE_PARTITION = 'local.Sales360';

    // Platform Cache minimum TTL is 300 seconds; we use 3600 (1 hour)
    private static final Integer L1_TTL_SECONDS = 3600;

    /**
     * Looks up a cached response. Checks L1 (Platform Cache) first, then L2 (Custom Object).
     */
    public static String getCached(String userId, String fiscalPeriod,
                                    String responseType) {
        String l1Key = buildL1Key(userId, fiscalPeriod, responseType);
        String l2Key = buildKey(userId, fiscalPeriod, responseType);

        // L1: Platform Cache (uses alphanumeric key)
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition != null) {
                Object cached = partition.get(l1Key);
                if (cached != null) {
                    incrementHitCount(l2Key);
                    return (String) cached;
                }
            }
        } catch (Exception ignored) {
            // Platform Cache not configured - fall through to L2
        }

        // L2: Custom Object (uses human-readable pipe-separated key as Name)
        List<EK_Sales360_Cache__c> records = [
            SELECT JSON_Payload__c, Expires_At__c, Hit_Count__c
            FROM EK_Sales360_Cache__c
            WHERE Name = :l2Key
              AND Expires_At__c > :Datetime.now()
              AND Is_Stale__c = false
            LIMIT 1
        ];

        if (records.isEmpty()) {
            return null;
        }

        // Promote L2 hit to L1 for faster subsequent access
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition != null) {
                partition.put(l1Key, records[0].JSON_Payload__c, L1_TTL_SECONDS);
            }
        } catch (Exception ignored) {}

        incrementHitCount(l2Key);
        return records[0].JSON_Payload__c;
    }

    /**
     * Writes a generated response to the cache (both L1 and L2).
     * Uses the default TTL for the response type.
     */
    public static void cache(String userId, String fiscalPeriod,
                              String responseType, String jsonPayload,
                              Long generationTimeMs, String source) {
        cache(userId, fiscalPeriod, responseType, jsonPayload,
              generationTimeMs, source, null);
    }

    /**
     * Writes a generated response with an optional TTL override (in hours).
     */
    public static void cache(String userId, String fiscalPeriod,
                              String responseType, String jsonPayload,
                              Long generationTimeMs, String source,
                              Integer ttlHoursOverride) {

        String l1Key = buildL1Key(userId, fiscalPeriod, responseType);
        String l2Key = buildKey(userId, fiscalPeriod, responseType);
        Datetime now = Datetime.now();
        Integer ttlHours = (ttlHoursOverride != null) ? ttlHoursOverride :
                           ('MY_PERFORMANCE_KPI'.equals(responseType) ? KPI_TTL_HOURS :
                            DEFAULT_TTL_HOURS);
        Datetime expiry = now.addHours(ttlHours);

        // L2: Upsert custom object (Name field allows pipe-separated key)
        EK_Sales360_Cache__c record = new EK_Sales360_Cache__c(
            Name = l2Key,
            User_Id__c = userId,
            Fiscal_Period__c = fiscalPeriod,
            Response_Type__c = responseType,
            Schema_Version__c = '1.0',
            JSON_Payload__c = jsonPayload,
            Generated_At__c = now,
            Expires_At__c = expiry,
            Hit_Count__c = 0,
            Generation_Source__c = source,
            Generation_Time_Ms__c = generationTimeMs,
            Is_Stale__c = false
        );

        // Upsert by Name
        List<EK_Sales360_Cache__c> existing = [
            SELECT Id FROM EK_Sales360_Cache__c WHERE Name = :l2Key LIMIT 1
        ];
        if (!existing.isEmpty()) {
            record.Id = existing[0].Id;
        }
        upsert record;

        // L1: Platform Cache (uses alphanumeric key)
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition != null) {
                partition.put(l1Key, jsonPayload, L1_TTL_SECONDS);
            }
        } catch (Exception ignored) {}
    }

    /**
     * Invalidates a specific cache entry. Called when the user clicks Refresh.
     */
    public static void invalidate(String userId, String fiscalPeriod,
                                   String responseType) {
        String l1Key = buildL1Key(userId, fiscalPeriod, responseType);
        String l2Key = buildKey(userId, fiscalPeriod, responseType);

        // L1: Remove from Platform Cache
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition != null) {
                partition.remove(l1Key);
            }
        } catch (Exception ignored) {}

        // L2: Mark as stale (preserves history for telemetry)
        List<EK_Sales360_Cache__c> existing = [
            SELECT Id FROM EK_Sales360_Cache__c WHERE Name = :l2Key LIMIT 1
        ];
        if (!existing.isEmpty()) {
            existing[0].Is_Stale__c = true;
            update existing[0];
        }
    }

    /**
     * Builds the human-readable L2 cache key used as the Name of EK_Sales360_Cache__c.
     * Format: userId|fiscalPeriod|responseType (e.g., USER_001|FY26Q1|PORTFOLIO_SUMMARY)
     */
    @TestVisible
    private static String buildKey(String userId, String fiscalPeriod,
                                    String responseType) {
        return userId + '|' + fiscalPeriod + '|' + responseType;
    }

    /**
     * Builds the L1 cache key for Platform Cache (alphanumeric only).
     * Platform Cache keys cannot contain underscores, pipes, or other special characters.
     * Strips all non-alphanumeric characters from the composite key.
     *
     * Example: 'USER_001|FY26Q1|PORTFOLIO_SUMMARY' -> 'USER001FY26Q1PORTFOLIOSUMMARY'
     */
    @TestVisible
    private static String buildL1Key(String userId, String fiscalPeriod,
                                      String responseType) {
        String raw = (userId == null ? '' : userId)
                   + (fiscalPeriod == null ? '' : fiscalPeriod)
                   + (responseType == null ? '' : responseType);
        return raw.replaceAll('[^a-zA-Z0-9]', '');
    }

    private static void incrementHitCount(String l2Key) {
        // Best-effort increment - fire and forget
        try {
            List<EK_Sales360_Cache__c> existing = [
                SELECT Id, Hit_Count__c FROM EK_Sales360_Cache__c
                WHERE Name = :l2Key LIMIT 1
            ];
            if (!existing.isEmpty()) {
                Decimal current = existing[0].Hit_Count__c == null ?
                    0 : existing[0].Hit_Count__c;
                existing[0].Hit_Count__c = current + 1;
                update existing[0];
            }
        } catch (Exception ignored) {}
    }
}
