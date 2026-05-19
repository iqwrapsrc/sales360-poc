/**
 * @description  Controller for the Opportunity Spotlight panel LWC.
 *               Symmetric to Sales360PortfolioController - same cache + LLM pattern, different data.
 *
 * @author       Anup Chandran (Emirates Group IT)
 * @phase        Sales360 PoC - Phase 7
 * @since        May 2026
 */
public with sharing class Sales360SpotlightController {

    private static final String RESPONSE_TYPE = 'OPPORTUNITY_SPOTLIGHT';
    private static final String TEMPLATE_API_NAME = 'Opportunity_Spotlight_JSON_Template';

    @AuraEnabled(cacheable=true)
    public static String getSpotlightJson(String userId, String fiscalPeriod) {
        try {
            if (String.isBlank(fiscalPeriod)) {
                fiscalPeriod = computeCurrentFiscalPeriod();
            }

            String ownerId = UserMappingService.resolveOwnerId(
                UserInfo.getUserId(), userId);

            String cached = Sales360CacheService.getCached(
                ownerId, fiscalPeriod, RESPONSE_TYPE);
            if (String.isNotBlank(cached)) {
                return cached;
            }

            return generateFresh(ownerId, fiscalPeriod, 'APEX_FRESH');

        } catch (Exception e) {
            return buildErrorResponse(userId, fiscalPeriod, e.getMessage());
        }
    }

    @AuraEnabled
    public static String refreshSpotlight(String userId, String fiscalPeriod) {
        try {
            if (String.isBlank(fiscalPeriod)) {
                fiscalPeriod = computeCurrentFiscalPeriod();
            }
            String ownerId = UserMappingService.resolveOwnerId(
                UserInfo.getUserId(), userId);

            Sales360CacheService.invalidate(ownerId, fiscalPeriod, RESPONSE_TYPE);
            return generateFresh(ownerId, fiscalPeriod, 'MANUAL_REFRESH');

        } catch (Exception e) {
            return buildErrorResponse(userId, fiscalPeriod, e.getMessage());
        }
    }

    private static String generateFresh(String ownerId, String fiscalPeriod,
                                          String source) {
        Long startMs = System.currentTimeMillis();

        List<Map<String, Object>> odPairData =
            Sales360DataService.getOpportunitySpotlightData(ownerId, fiscalPeriod);

        if (odPairData.isEmpty()) {
            return buildEmptyResponse(ownerId, fiscalPeriod);
        }

        String odPairDataJson = JSON.serialize(odPairData);

        Map<String, String> inputParams = new Map<String, String>{
            'userId' => ownerId,
            'fiscalPeriod' => fiscalPeriod,
            'odPairDataJson' => odPairDataJson
        };

        String jsonResponse = PromptTemplateInvoker.invoke(
            TEMPLATE_API_NAME, inputParams);

        Long generationMs = System.currentTimeMillis() - startMs;
        Sales360CacheService.cache(
            ownerId, fiscalPeriod, RESPONSE_TYPE,
            jsonResponse, generationMs, source);

        return jsonResponse;
    }

    private static String buildEmptyResponse(String userId, String fiscalPeriod) {
        Map<String, Object> emptyJson = new Map<String, Object>{
            'schemaVersion' => '1.0',
            'responseType' => RESPONSE_TYPE,
            'context' => new Map<String, Object>{
                'userId' => userId,
                'fiscalPeriod' => fiscalPeriod,
                'currency' => 'AED',
                'generatedAt' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
            },
            'summary' => new Map<String, Object>{
                'totalOpportunitiesCovered' => 0,
                'redCount' => 0, 'amberCount' => 0, 'greenCount' => 0,
                'headlineNarrative' => 'No opportunities identified.'
            },
            'spotlights' => new List<Object>()
        };
        return JSON.serialize(emptyJson);
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
            'spotlights' => new List<Object>(),
            'summary' => new Map<String, Object>{
                'totalOpportunitiesCovered' => 0,
                'redCount' => 0, 'amberCount' => 0, 'greenCount' => 0,
                'headlineNarrative' => 'Unable to generate insights: ' + errorMsg
            }
        };
        return JSON.serialize(errorJson);
    }

    private static String computeCurrentFiscalPeriod() {
        Date today = Date.today();
        Integer quarter = ((today.month() - 1) / 3) + 1;
        return 'FY' + String.valueOf(today.year()).right(2) + 'Q' + String.valueOf(quarter);
    }
}
