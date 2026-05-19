/**
 * @description  Controller for the My Performance KPI bar LWC.
 *               PoC version - no caching. Every call regenerates fresh.
 *               No LLM involved - pure deterministic aggregation via KpiAggregationService.
 *
 *               Method names aligned to LWC import:
 *                 import getMyPerformanceKpis from '@salesforce/apex/Sales360KpiController.getMyPerformanceKpis';
 *                 import refreshMyPerformanceKpis from '@salesforce/apex/Sales360KpiController.refreshMyPerformanceKpis';
 *
 * @author       Anup Chandran (Emirates Group IT)
 * @phase        Sales360 PoC - Phase 7
 * @since        May 2026
 * @updated      May 2026 - Cache layer removed for PoC simplification
 */
public with sharing class Sales360KpiController {

    private static final String RESPONSE_TYPE = 'MY_PERFORMANCE_KPI';

    @AuraEnabled(cacheable=true)
    public static String getMyPerformanceKpis(String userId, String fiscalPeriod) {
        try {
            if (String.isBlank(fiscalPeriod)) {
                fiscalPeriod = computeCurrentFiscalPeriod();
            }
            String ownerId = UserMappingService.resolveOwnerId(
                UserInfo.getUserId(), userId);

            Map<String, Object> kpis = KpiAggregationService.getMyPerformanceKpis(
                ownerId, fiscalPeriod);
            return JSON.serialize(kpis);

        } catch (Exception e) {
            return buildErrorResponse(userId, fiscalPeriod, e.getMessage());
        }
    }

    @AuraEnabled
    public static String refreshMyPerformanceKpis(String userId, String fiscalPeriod) {
        // No cache to invalidate - just regenerate
        try {
            if (String.isBlank(fiscalPeriod)) {
                fiscalPeriod = computeCurrentFiscalPeriod();
            }
            String ownerId = UserMappingService.resolveOwnerId(
                UserInfo.getUserId(), userId);

            Map<String, Object> kpis = KpiAggregationService.getMyPerformanceKpis(
                ownerId, fiscalPeriod);
            return JSON.serialize(kpis);

        } catch (Exception e) {
            return buildErrorResponse(userId, fiscalPeriod, e.getMessage());
        }
    }

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
            'kpis' => new List<Object>()
        };
        return JSON.serialize(errorJson);
    }

    private static String computeCurrentFiscalPeriod() {
        Date today = Date.today();
        Integer quarter = ((today.month() - 1) / 3) + 1;
        return 'FY' + String.valueOf(today.year()).right(2) + 'Q' + String.valueOf(quarter);
    }
}
