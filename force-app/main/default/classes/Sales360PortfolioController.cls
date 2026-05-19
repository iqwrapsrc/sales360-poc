/**
 * @description  Controller for the Portfolio Summary panel LWC.
 *               PoC version - no caching. Every call regenerates fresh.
 *               LWC @wire framework provides in-session client-side caching.
 *
 * @author       Anup Chandran (Emirates Group IT)
 * @phase        Sales360 PoC - Phase 7
 * @since        May 2026
 * @updated      May 2026 - Cache layer removed for PoC simplification
 */
public with sharing class Sales360PortfolioController {

    private static final String RESPONSE_TYPE = 'PORTFOLIO_SUMMARY';
    private static final String TEMPLATE_API_NAME = 'Portfolio_Summary_JSON_Template';

    @AuraEnabled(cacheable=true)
    public static String getPortfolioJson(String userId, String fiscalPeriod) {
        try {
            if (String.isBlank(fiscalPeriod)) {
                fiscalPeriod = computeCurrentFiscalPeriod();
            }
            String ownerId = UserMappingService.resolveOwnerId(
                UserInfo.getUserId(), userId);

            return generatePortfolio(ownerId, fiscalPeriod);

        } catch (Exception e) {
            return buildErrorResponse(userId, fiscalPeriod, e.getMessage());
        }
    }

    @AuraEnabled
    public static String refreshPortfolio(String userId, String fiscalPeriod) {
        // No cache to invalidate - just regenerate
        try {
            if (String.isBlank(fiscalPeriod)) {
                fiscalPeriod = computeCurrentFiscalPeriod();
            }
            String ownerId = UserMappingService.resolveOwnerId(
                UserInfo.getUserId(), userId);

            return generatePortfolio(ownerId, fiscalPeriod);

        } catch (Exception e) {
            return buildErrorResponse(userId, fiscalPeriod, e.getMessage());
        }
    }

    private static String generatePortfolio(String ownerId, String fiscalPeriod) {

        List<Map<String, Object>> agencyData =
            Sales360DataService.getAgencyPortfolioData(ownerId, fiscalPeriod);

        if (agencyData.isEmpty()) {
            return buildEmptyResponse(ownerId, fiscalPeriod);
        }

        String agencyDataJson = JSON.serialize(agencyData);

        Map<String, String> inputParams = new Map<String, String>{
            'userId' => ownerId,
            'fiscalPeriod' => fiscalPeriod,
            'agencyDataJson' => agencyDataJson
        };

        return PromptTemplateInvoker.invoke(TEMPLATE_API_NAME, inputParams);
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
                'totalAgenciesCovered' => 0,
                'redCount' => 0, 'amberCount' => 0, 'greenCount' => 0,
                'headlineNarrative' => 'No agencies found for this user.'
            },
            'agencies' => new List<Object>()
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
            'agencies' => new List<Object>(),
            'summary' => new Map<String, Object>{
                'totalAgenciesCovered' => 0,
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
