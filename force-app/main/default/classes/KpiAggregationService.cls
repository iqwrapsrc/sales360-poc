/**
 * @description  Aggregates the 4 headline KPIs (Flown Revenue, Flown PAX, Forward Revenue, Forward PAX)
 *               for the My Performance KPI Bar. Computes year-over-year deltas using deterministic
 *               arithmetic - no LLM involvement.
 *
 *               This is the FAST path of the Unified Desktop - typically completes in 1-2 seconds
 *               while the AI panels below are still generating.
 *
 * @author       Anup Chandran (Emirates Group IT)
 * @phase        Sales360 PoC - Phase 7
 * @since        May 2026
 * @updated      May 2026 - Hardened sumCI() against Connect API proxy fault in @AuraEnabled(cacheable=true)
 *                          context. The platform-level "Internal Salesforce.com Error" fault was
 *                          observed at row.get(alias) immediately after a successful CdpQuery SUM
 *                          aggregation, bypassing the try/catch. Defensive JSON serialize/deserialize
 *                          converts the Connect API result proxy into a native Apex HashMap before
 *                          key access; snake_case alias matches Data Cloud's Trino-based identifier
 *                          folding; multi-casing key lookup tolerates engine behaviour drift.
 */
public with sharing class KpiAggregationService {

    /**
     * Returns the 4 headline KPIs with YoY deltas for the given owner and period.
     */
    public static Map<String, Object> getMyPerformanceKpis(
            String ownerUserId, String fiscalPeriod) {

        Map<String, String> currentPeriod = parseFiscalPeriod(fiscalPeriod);
        Map<String, String> priorPeriod = computePriorYearPeriod(currentPeriod);

        Map<String, Decimal> current =
            aggregateAllKpis(ownerUserId, currentPeriod);
        Map<String, Decimal> prior =
            aggregateAllKpis(ownerUserId, priorPeriod);

        return new Map<String, Object>{
            'schemaVersion' => '1.0',
            'responseType' => 'MY_PERFORMANCE_KPI',
            'context' => new Map<String, Object>{
                'userId' => ownerUserId,
                'fiscalPeriod' => fiscalPeriod,
                'currency' => 'AED',
                'generatedAt' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
            },
            'kpis' => new List<Map<String, Object>>{
                buildKpiCard('FLOWN_REVENUE', 'Flown Revenue',
                    current.get('flownRevenue'), prior.get('flownRevenue'),
                    'CURRENCY'),
                buildKpiCard('FLOWN_PAX', 'Flown PAX',
                    current.get('flownPax'), prior.get('flownPax'),
                    'COUNT'),
                buildKpiCard('FORWARD_REVENUE', 'Forward Revenue',
                    current.get('forwardRevenue'), prior.get('forwardRevenue'),
                    'CURRENCY'),
                buildKpiCard('FORWARD_PAX', 'Forward PAX',
                    current.get('forwardPax'), prior.get('forwardPax'),
                    'COUNT')
            }
        };
    }

    @TestVisible
    private static Map<String, Decimal> aggregateAllKpis(
            String ownerUserId, Map<String, String> period) {

        Map<String, Decimal> result = new Map<String, Decimal>{
            'flownRevenue' => 0,
            'flownPax' => 0,
            'forwardRevenue' => 0,
            'forwardPax' => 0
        };

        result.put('flownRevenue', sumCI(ownerUserId, period,
            'Flown_Revenue_By_Agency__cio', 'flown_revenue_aed__c'));
        result.put('flownPax', sumCI(ownerUserId, period,
            'Flown_PAX_By_Agency__cio', 'flown_pax__c'));
        result.put('forwardRevenue', sumCI(ownerUserId, period,
            'Forward_Revenue_By_Agency__cio', 'forward_revenue_aed__c'));
        result.put('forwardPax', sumCI(ownerUserId, period,
            'Forward_PAX_By_Agency__cio', 'forward_pax__c'));

        return result;
    }

    /**
     * Returns the SUM of a single CI's value field across all agencies owned by the user.
     *
     * Hardening notes (May 2026):
     * - The result row from ConnectApi.CdpQuery is a proxy object, not a native HashMap.
     *   In @AuraEnabled(cacheable=true) context this proxy can trip a platform-level
     *   "Internal Salesforce.com Error" fault on Map.get() which bypasses try/catch.
     *   We serialize/deserialize through JSON to materialize a native HashMap before
     *   any key access.
     * - Data Cloud's Trino-based SQL engine folds unquoted identifiers to lowercase,
     *   so the alias 'totalValue' would arrive as 'totalvalue'. We use snake_case
     *   'total_value' as the canonical alias and probe multiple casings on read.
     */
    @TestVisible
    private static Decimal sumCI(String ownerUserId, Map<String, String> period,
                                  String ciName, String valueField) {

        List<SObject> agencies = Database.query(
            'SELECT agency_id__c FROM Agency__dlm ' +
            'WHERE owner_user_id__c = :ownerUserId'
        );
        if (agencies.isEmpty()) return 0;

        Set<String> agencyIds = new Set<String>();
        for (SObject a : agencies) agencyIds.add((String) a.get('agency_id__c'));

        String inClause = '\'' + String.join(new List<String>(agencyIds), '\',\'') + '\'';

        String sql = 'SELECT SUM(' + valueField + ') AS total_value '
                   + 'FROM ' + ciName + ' '
                   + 'WHERE agency_id__c IN (' + inClause + ') '
                   + 'AND fiscal_year__c = \'' + period.get('year') + '\' '
                   + 'AND fiscal_quarter__c = \'' + period.get('quarter') + '\'';

        ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
        input.sql = sql;

        try {
            ConnectApi.CdpQueryOutput output = ConnectApi.CdpQuery.queryAnsiSql(input);
            if (output == null || output.data == null || output.data.isEmpty()) {
                return 0;
            }

            // Convert Connect API proxy result into a native Apex map via JSON.
            // This is what dodges the platform fault observed at row.get(...) in
            // cacheable=true contexts.
            String dataJson = JSON.serialize(output.data);
            List<Object> rows = (List<Object>) JSON.deserializeUntyped(dataJson);
            if (rows == null || rows.isEmpty()) return 0;

            Object firstRow = rows[0];
            if (firstRow == null || !(firstRow instanceof Map<String, Object>)) {
                return 0;
            }
            Map<String, Object> row = (Map<String, Object>) firstRow;
            if (row.isEmpty()) return 0;

            // Probe multiple casings - Data Cloud SQL identifier folding behaviour
            // can vary by engine version and quoting.
            Object v = row.get('total_value');
            if (v == null) v = row.get('totalValue');
            if (v == null) v = row.get('TOTAL_VALUE');
            if (v == null) v = row.get('TOTALVALUE');
            if (v == null) {
                // Final fallback - grab the first value regardless of key name
                for (Object val : row.values()) {
                    v = val;
                    break;
                }
            }
            return toDecimal(v);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'CdpQuery SUM failed for ' + ciName + ': ' + e.getMessage());
        }
        return 0;
    }

    @TestVisible
    private static Map<String, Object> buildKpiCard(String kpiId, String label,
            Decimal current, Decimal prior, String valueType) {

        current = (current == null) ? 0 : current;
        prior = (prior == null) ? 0 : prior;

        Decimal yoyPct;
        String trend;

        if (prior == 0) {
            yoyPct = null;
            trend = 'FLAT';
        } else {
            yoyPct = ((current - prior) / prior * 100).setScale(1);
            if (yoyPct > 0.5) {
                trend = 'UP';
            } else if (yoyPct < -0.5) {
                trend = 'DOWN';
            } else {
                trend = 'FLAT';
            }
        }

        return new Map<String, Object>{
            'kpiId' => kpiId,
            'label' => label,
            'value' => current,
            'displayValue' => formatValue(current, valueType),
            'yoyPct' => yoyPct,
            'yoyDisplay' => formatYoY(yoyPct),
            'trend' => trend
        };
    }

    @TestVisible
    private static String formatValue(Decimal value, String type) {
        if (value == null) return '-';
        if ('CURRENCY'.equals(type)) {
            if (value >= 1000000) {
                return 'AED ' + (value / 1000000).setScale(1) + 'M';
            } else if (value >= 1000) {
                return 'AED ' + (value / 1000).setScale(1) + 'K';
            }
            return 'AED ' + value.setScale(0);
        } else {
            if (value >= 1000000) {
                return (value / 1000000).setScale(1) + 'M';
            } else if (value >= 1000) {
                return (value / 1000).setScale(1) + 'K';
            }
            return String.valueOf(value.intValue());
        }
    }

    @TestVisible
    private static String formatYoY(Decimal yoyPct) {
        if (yoyPct == null) return '-';
        String sign = (yoyPct >= 0) ? '+' : '';
        return sign + String.valueOf(yoyPct) + '%';
    }

    @TestVisible
    private static Map<String, String> parseFiscalPeriod(String fiscalPeriod) {
        Map<String, String> parts = new Map<String, String>();
        if (String.isBlank(fiscalPeriod) || fiscalPeriod.length() < 6) {
            parts.put('year', '2026');
            parts.put('quarter', '1');
            return parts;
        }
        String year = '20' + fiscalPeriod.substring(2, 4);
        String quarter = fiscalPeriod.right(1);
        parts.put('year', year);
        parts.put('quarter', quarter);
        return parts;
    }

    @TestVisible
    private static Map<String, String> computePriorYearPeriod(
            Map<String, String> currentPeriod) {
        Map<String, String> prior = new Map<String, String>();
        Integer currentYear = Integer.valueOf(currentPeriod.get('year'));
        prior.put('year', String.valueOf(currentYear - 1));
        prior.put('quarter', currentPeriod.get('quarter'));
        return prior;
    }

    @TestVisible
    private static Decimal toDecimal(Object value) {
        if (value == null) return 0;
        if (value instanceof Decimal) return (Decimal) value;
        if (value instanceof Integer) return (Decimal) ((Integer) value);
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return 0;
        }
    }
}
