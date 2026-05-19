/**
 * @description  Controller for the My Performance KPI Bar LWC.
 *               Provides cached read access plus an explicit refresh path.
 *               Does NOT invoke the LLM - this is the FAST path that loads in 1-2 seconds.
 *
 * @author       Anup Chandran (Emirates Group IT)
 * @phase        Sales360 PoC - Phase 7
 * @since        May 2026
 */
public with sharing class Sales360KpiController {

    private static final String RESPONSE_TYPE = 'MY_PERFORMANCE_KPI';

    /**
     * Cached read path. LWC @wire will call this on component load.
     *
     * @param userId        Optional persona override from LWC (or empty string for default)
     * @param fiscalPeriod  E.g., 'FY26Q1'
     * @return              MY_PERFORMANCE_KPI JSON string
     */
    @AuraEnabled(cacheable=true)
    public static String getMyPerformanceKpis(String userId, String fiscalPeriod) {
        try {
            if (String.isBlank(fiscalPeriod)) {
                fiscalPeriod = computeCurrentFiscalPeriod();
            }

            // Resolve to demo persona owner ID
            String ownerId = UserMappingService.resolveOwnerId(
                UserInfo.getUserId(), userId);

            // 6-hour TTL cache lookup
            String cached = Sales360CacheService.getCached(
                ownerId, fiscalPeriod, RESPONSE_TYPE);
            if (String.isNotBlank(cached)) {
                return cached;
            }

            // Cache miss - generate fresh (no LLM, fast)
            return generateFresh(ownerId, fiscalPeriod, 'APEX_FRESH');

        } catch (Exception e) {
            return buildErrorResponse(userId, fiscalPeriod, e.getMessage());
        }
    }

    /**
     * Explicit refresh path. LWC calls this when user clicks the refresh button.
     */
    @AuraEnabled
    public static String refreshMyPerformanceKpis(String userId, String fiscalPeriod) {
        try {
            if (String.isBlank(fiscalPeriod)) {
                fiscalPeriod = computeCurrentFiscalPeriod();
            }
            String ownerId = UserMappingService.resolveOwnerId(
                UserInfo.getUserId(), userId);

            // Invalidate existing cache
            Sales360CacheService.invalidate(ownerId, fiscalPeriod, RESPONSE_TYPE);

            // Generate fresh
            return generateFresh(ownerId, fiscalPeriod, 'MANUAL_REFRESH');

        } catch (Exception e) {
            return buildErrorResponse(userId, fiscalPeriod, e.getMessage());
        }
    }

    /**
     * Shared fresh-generation path (used by both cache-miss and explicit refresh).
     */
    private static String generateFresh(String ownerId, String fiscalPeriod,
                                          String source) {
        Long startMs = System.currentTimeMillis();

        Map<String, Object> kpiData =
            KpiAggregationService.getMyPerformanceKpis(ownerId, fiscalPeriod);

        Long generationMs = System.currentTimeMillis() - startMs;
        String jsonResponse = JSON.serialize(kpiData);

        // Cache with 6-hour TTL (override default 24h)
        Sales360CacheService.cache(
            ownerId, fiscalPeriod, RESPONSE_TYPE,
            jsonResponse, generationMs, source, 6);

        return jsonResponse;
    }

    /**
     * Builds an error JSON response that conforms to the MY_PERFORMANCE_KPI schema.
     * Ensures the LWC always receives parseable JSON.
     */
    private static String buildErrorResponse(String userId, String fiscalPeriod,
                                               String errorMsg) {
        Map<String, Object> errorJson = new Map<String, Object>{
            'schemaVersion' => '1.0',
            'responseType' => RESPONSE_TYPE,
            'context' => new Map<String, Object>{
                'userId' => userId,
                'fiscalPeriod' => fiscalPeriod,
                'currency' => 'AED',
                'generatedAt' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
            },
            'error' => new Map<String, Object>{
                'message' => errorMsg,
                'isRetryable' => true
            },
            'kpis' => new List<Map<String, Object>>()
        };
        return JSON.serialize(errorJson);
    }

    /**
     * Computes the current fiscal quarter (FY26Q1, etc.) based on today's date.
     * Emirates fiscal year aligns with calendar year for the PoC.
     */
    private static String computeCurrentFiscalPeriod() {
        Date today = Date.today();
        Integer year = today.year();
        Integer month = today.month();
        Integer quarter = ((month - 1) / 3) + 1;
        String yearShort = String.valueOf(year).right(2);
        return 'FY' + yearShort + 'Q' + String.valueOf(quarter);
    }
}
