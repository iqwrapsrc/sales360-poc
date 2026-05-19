/**
 * @description  Two-layer cache service for Sales360 AI responses.
 *               L1: Platform Cache (org partition 'Sales360') - sub-second access
 *               L2: EK_Sales360_Cache__c custom object - persistent across app server restarts
 *
 *               Cache keys follow the format: 'userId|fiscalPeriod|responseType'
 *               Different response types can have different TTL values.
 *
 * @author       Anup Chandran (Emirates Group IT)
 * @phase        Sales360 PoC - Phase 7
 * @since        May 2026
 */
public with sharing class Sales360CacheService {

    @TestVisible
    private static final Integer DEFAULT_TTL_HOURS = 24;

    @TestVisible
    private static final Integer KPI_TTL_HOURS = 6;

    @TestVisible
    private static final String CACHE_PARTITION = 'local.Sales360';

    private static final Integer L1_TTL_SECONDS = 3600;

    /**
     * Looks up a cached response. Checks L1 (Platform Cache) first, then L2 (Custom Object).
     *
     * @param userId        The owner user ID (e.g., 'USER_001')
     * @param fiscalPeriod  The fiscal period (e.g., 'FY26Q1')
     * @param responseType  One of MY_PERFORMANCE_KPI, PORTFOLIO_SUMMARY, OPPORTUNITY_SPOTLIGHT
     * @return              Cached JSON string, or null if no valid cache entry exists
     */
    public static String getCached(String userId, String fiscalPeriod,
                                    String responseType) {
        String cacheKey = buildKey(userId, fiscalPeriod, responseType);

        // L1: Platform Cache
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition != null) {
                Object cached = partition.get(cacheKey);
                if (cached != null) {
                    incrementHitCount(cacheKey);
                    return (String) cached;
                }
            }
        } catch (Exception ignored) {
            // Platform Cache not configured - fall through to L2
        }

        // L2: Custom Object
        List<EK_Sales360_Cache__c> records = [
            SELECT JSON_Payload__c, Expires_At__c, Hit_Count__c
            FROM EK_Sales360_Cache__c
            WHERE Name = :cacheKey
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
                partition.put(cacheKey, records[0].JSON_Payload__c, L1_TTL_SECONDS);
            }
        } catch (Exception ignored) {}

        incrementHitCount(cacheKey);
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

        String cacheKey = buildKey(userId, fiscalPeriod, responseType);
        Datetime now = Datetime.now();
        Integer ttlHours = (ttlHoursOverride != null) ? ttlHoursOverride :
                           ('MY_PERFORMANCE_KPI'.equals(responseType) ? KPI_TTL_HOURS :
                            DEFAULT_TTL_HOURS);
        Datetime expiry = now.addHours(ttlHours);

        // L2: Upsert custom object
        EK_Sales360_Cache__c record = new EK_Sales360_Cache__c(
            Name = cacheKey,
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

        // Upsert by Name (External ID would be better but Name works as key)
        List<EK_Sales360_Cache__c> existing = [
            SELECT Id FROM EK_Sales360_Cache__c WHERE Name = :cacheKey LIMIT 1
        ];
        if (!existing.isEmpty()) {
            record.Id = existing[0].Id;
        }
        upsert record;

        // L1: Platform Cache (1 hour to encourage L2 verification)
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition != null) {
                partition.put(cacheKey, jsonPayload, L1_TTL_SECONDS);
            }
        } catch (Exception ignored) {}
    }

    /**
     * Invalidates a specific cache entry. Called when the user clicks Refresh.
     */
    public static void invalidate(String userId, String fiscalPeriod,
                                   String responseType) {
        String cacheKey = buildKey(userId, fiscalPeriod, responseType);

        // L1: Remove from Platform Cache
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition != null) {
                partition.remove(cacheKey);
            }
        } catch (Exception ignored) {}

        // L2: Mark as stale (preserves history for telemetry)
        List<EK_Sales360_Cache__c> existing = [
            SELECT Id FROM EK_Sales360_Cache__c WHERE Name = :cacheKey LIMIT 1
        ];
        if (!existing.isEmpty()) {
            existing[0].Is_Stale__c = true;
            update existing[0];
        }
    }

    @TestVisible
    private static String buildKey(String userId, String fiscalPeriod,
                                    String responseType) {
        return userId + '|' + fiscalPeriod + '|' + responseType;
    }

    private static void incrementHitCount(String cacheKey) {
        // Best-effort increment - fire and forget
        try {
            List<EK_Sales360_Cache__c> existing = [
                SELECT Id, Hit_Count__c FROM EK_Sales360_Cache__c
                WHERE Name = :cacheKey LIMIT 1
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
