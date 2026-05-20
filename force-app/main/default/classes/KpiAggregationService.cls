/**
 * @description  Aggregates the 8 headline KPIs for the My Performance KPI Bar.
 *               Deterministic arithmetic - no LLM involvement.
 *
 *               KPI set:
 *                 1. Flown Revenue        (Flown_Revenue_By_Agency__cio.flown_revenue_aed__c)   CURRENCY
 *                 2. Flown PAX            (Flown_PAX_By_Agency__cio.flown_pax_count__c)          COUNT
 *                 3. Forward Revenue      (Forward_Revenue_By_Agency__cio.forward_revenue_aed__c) CURRENCY
 *                 4. Forward PAX          (Forward_PAX_By_Agency__cio.forward_pax_count__c)       COUNT
 *                 5. Flown Yield          (Flown_Yield_By_Agency__cio.flown_yield_aed__c)         CURRENCY (avg)
 *                 6. Flown Bookings       (Flown_Bookings_By_Agency__cio.flown_bookings_count__c) COUNT
 *                 7. Target Attainment    (FY_Target_Attainment_By_Agency__cio.target_attainment_ratio__c) PERCENT - YEAR ONLY
 *                 8. Market Share         (EK_Market_Share_By_OD_Pair__cio.ek_market_share_ratio__c) PERCENT (avg, by od_pair)
 *
 * @author       Anup Chandran (Emirates Group IT)
 * @phase        Sales360 PoC - Phase 7
 * @since        May 2026
 * @updated      May 2026 - Expanded 4 -> 8 cards. Reuses the proven access pattern:
 *                          ConnectApi.CdpQuery rows are ApexMapWrapper (cannot cast to Map or
 *                          JSON.serialize), so the aggregate value is read by parsing
 *                          String.valueOf(row) for 'total_value='. Period filter uses the full
 *                          fiscal_quarter__c token ('FY26Q1'); Target Attainment filters
 *                          fiscal_year__c (numeric) only as that CI has no quarter dimension.
 */
public with sharing class KpiAggregationService {

    public static Map<String, Object> getMyPerformanceKpis(
            String ownerUserId, String fiscalPeriod) {

        String currentPeriod = normalizePeriod(fiscalPeriod);
        String priorPeriod = computePriorYearPeriod(currentPeriod);
        Integer currentYear = periodToYear(currentPeriod);
        Integer priorYear = (currentYear == null) ? null : currentYear - 1;

        // Agency-keyed metrics (quarter-filtered SUMs)
        Map<String, Decimal> cur = aggregateAgencyKpis(ownerUserId, currentPeriod);
        Map<String, Decimal> pri = aggregateAgencyKpis(ownerUserId, priorPeriod);

        // Target Attainment - year-only, AVG of ratio
        Decimal curAttain = avgTargetAttainment(ownerUserId, currentYear);
        Decimal priAttain = avgTargetAttainment(ownerUserId, priorYear);

        // Market Share - by OD pair, AVG of ratio for the period
        Decimal curShare = avgMarketShare(currentPeriod);
        Decimal priShare = avgMarketShare(priorPeriod);

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
                    cur.get('flownRevenue'), pri.get('flownRevenue'), 'CURRENCY'),
                buildKpiCard('FLOWN_PAX', 'Flown PAX',
                    cur.get('flownPax'), pri.get('flownPax'), 'COUNT'),
                buildKpiCard('FORWARD_REVENUE', 'Forward Revenue',
                    cur.get('forwardRevenue'), pri.get('forwardRevenue'), 'CURRENCY'),
                buildKpiCard('FORWARD_PAX', 'Forward PAX',
                    cur.get('forwardPax'), pri.get('forwardPax'), 'COUNT'),
                buildKpiCard('FLOWN_YIELD', 'Flown Yield',
                    cur.get('flownYield'), pri.get('flownYield'), 'CURRENCY'),
                buildKpiCard('FLOWN_BOOKINGS', 'Flown Bookings',
                    cur.get('flownBookings'), pri.get('flownBookings'), 'COUNT'),
                buildKpiCard('TARGET_ATTAINMENT', 'Target Attainment',
                    curAttain, priAttain, 'PERCENT'),
                buildKpiCard('MARKET_SHARE', 'EK Market Share',
                    curShare, priShare, 'PERCENT')
            }
        };
    }

    /**
     * Six agency-keyed SUM metrics for one period.
     * Yield is averaged (it's a per-unit rate, summing makes no sense) - handled in sumOrAvgCI.
     */
    @TestVisible
    private static Map<String, Decimal> aggregateAgencyKpis(
            String ownerUserId, String period) {

        Map<String, Decimal> r = new Map<String, Decimal>{
            'flownRevenue' => 0, 'flownPax' => 0,
            'forwardRevenue' => 0, 'forwardPax' => 0,
            'flownYield' => 0, 'flownBookings' => 0
        };

        r.put('flownRevenue', sumCI(ownerUserId, period,
            'Flown_Revenue_By_Agency__cio', 'flown_revenue_aed__c', 'SUM'));
        r.put('flownPax', sumCI(ownerUserId, period,
            'Flown_PAX_By_Agency__cio', 'flown_pax_count__c', 'SUM'));
        r.put('forwardRevenue', sumCI(ownerUserId, period,
            'Forward_Revenue_By_Agency__cio', 'forward_revenue_aed__c', 'SUM'));
        r.put('forwardPax', sumCI(ownerUserId, period,
            'Forward_PAX_By_Agency__cio', 'forward_pax_count__c', 'SUM'));
        r.put('flownYield', sumCI(ownerUserId, period,
            'Flown_Yield_By_Agency__cio', 'flown_yield_aed__c', 'AVG'));
        r.put('flownBookings', sumCI(ownerUserId, period,
            'Flown_Bookings_By_Agency__cio', 'flown_bookings_count__c', 'SUM'));

        return r;
    }

    /**
     * Aggregate (SUM or AVG) of a CI value field across the user's agencies for a quarter.
     * period is the full fiscal token e.g. 'FY26Q1' matching fiscal_quarter__c directly.
     */
    @TestVisible
    private static Decimal sumCI(String ownerUserId, String period,
                                  String ciName, String valueField, String aggFn) {

        if (String.isBlank(period)) return 0;

        List<SObject> agencies = Database.query(
            'SELECT agency_id__c FROM Agency__dlm WHERE owner_user_id__c = :ownerUserId'
        );
        if (agencies.isEmpty()) return 0;

        Set<String> agencyIds = new Set<String>();
        for (SObject a : agencies) agencyIds.add((String) a.get('agency_id__c'));
        String inClause = '\'' + String.join(new List<String>(agencyIds), '\',\'') + '\'';

        String fn = ('AVG'.equals(aggFn)) ? 'AVG' : 'SUM';
        String sql = 'SELECT ' + fn + '(' + valueField + ') AS total_value '
                   + 'FROM ' + ciName + ' '
                   + 'WHERE agency_id__c IN (' + inClause + ') '
                   + 'AND fiscal_quarter__c = \'' + String.escapeSingleQuotes(period) + '\'';

        return runScalar(sql, ciName + '/' + period);
    }

    /**
     * AVG of target_attainment_ratio across the user's agencies for a fiscal YEAR.
     * FY_Target_Attainment_By_Agency__cio has no quarter dimension and fiscal_year__c is numeric.
     */
    @TestVisible
    private static Decimal avgTargetAttainment(String ownerUserId, Integer fiscalYear) {
        if (fiscalYear == null) return 0;

        List<SObject> agencies = Database.query(
            'SELECT agency_id__c FROM Agency__dlm WHERE owner_user_id__c = :ownerUserId'
        );
        if (agencies.isEmpty()) return 0;

        Set<String> agencyIds = new Set<String>();
        for (SObject a : agencies) agencyIds.add((String) a.get('agency_id__c'));
        String inClause = '\'' + String.join(new List<String>(agencyIds), '\',\'') + '\'';

        // fiscal_year__c is a NUMBER - no quotes
        String sql = 'SELECT AVG(target_attainment_ratio__c) AS total_value '
                   + 'FROM FY_Target_Attainment_By_Agency__cio '
                   + 'WHERE agency_id__c IN (' + inClause + ') '
                   + 'AND fiscal_year__c = ' + fiscalYear;

        Decimal ratio = runScalar(sql, 'Attainment/' + fiscalYear);
        // target_attainment_ratio__c is already stored as a 0..100 percentage
        // (NOT a 0..1 fraction), so no x100 scaling here.
        return (ratio == null) ? 0 : ratio;
    }

    /**
     * AVG of ek_market_share_ratio across all OD pairs for the period (blended share).
     * EK_Market_Share_By_OD_Pair__cio is keyed by od_pair_id__c, not agency.
     */
    @TestVisible
    private static Decimal avgMarketShare(String period) {
        if (String.isBlank(period)) return 0;
        String sql = 'SELECT AVG(ek_market_share_ratio__c) AS total_value '
                   + 'FROM EK_Market_Share_By_OD_Pair__cio '
                   + 'WHERE fiscal_quarter__c = \'' + String.escapeSingleQuotes(period) + '\'';
        Decimal ratio = runScalar(sql, 'MarketShare/' + period);
        return (ratio == null) ? 0 : ratio * 100;
    }

    /**
     * Executes a single-column aggregate query and returns the numeric value.
     * Connect API rows are ApexMapWrapper - read via String.valueOf parse (no cast, no JSON).
     */
    @TestVisible
    private static Decimal runScalar(String sql, String tag) {
        ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
        input.sql = sql;
        try {
            ConnectApi.CdpQueryOutput output = ConnectApi.CdpQuery.queryAnsiSql(input);
            if (output == null || output.data == null || output.data.isEmpty()) {
                return 0;
            }
            return extractTotalValue(String.valueOf(output.data[0]));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CdpQuery failed for ' + tag + ': ' + e.getMessage());
        }
        return 0;
    }

    @TestVisible
    private static Decimal extractTotalValue(String rowStr) {
        if (String.isBlank(rowStr)) return 0;
        String marker = 'total_value=';
        Integer p = rowStr.indexOf(marker);
        if (p < 0) return 0;
        String rest = rowStr.substring(p + marker.length());
        Integer endPos = rest.length();
        Integer bracePos = rest.indexOf('}');
        Integer commaPos = rest.indexOf(',');
        if (bracePos >= 0) endPos = Math.min(endPos, bracePos);
        if (commaPos >= 0) endPos = Math.min(endPos, commaPos);
        String token = rest.substring(0, endPos).trim();
        if (String.isBlank(token) || token == 'null') return 0;
        try {
            return Decimal.valueOf(token);
        } catch (Exception e) {
            return 0;
        }
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
            if (yoyPct > 0.5) trend = 'UP';
            else if (yoyPct < -0.5) trend = 'DOWN';
            else trend = 'FLAT';
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
        if ('PERCENT'.equals(type)) {
            return value.setScale(1) + '%';
        } else if ('CURRENCY'.equals(type)) {
            if (value >= 1000000) return 'AED ' + (value / 1000000).setScale(1) + 'M';
            if (value >= 1000) return 'AED ' + (value / 1000).setScale(1) + 'K';
            return 'AED ' + value.setScale(0);
        } else { // COUNT
            if (value >= 1000000) return (value / 1000000).setScale(1) + 'M';
            if (value >= 1000) return (value / 1000).setScale(1) + 'K';
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
    private static String normalizePeriod(String fiscalPeriod) {
        if (String.isBlank(fiscalPeriod)) return 'FY26Q1';
        String clean = fiscalPeriod.deleteWhitespace().toUpperCase();
        if (clean.contains('Q')) return clean;
        return clean + 'Q1';
    }

    @TestVisible
    private static String computePriorYearPeriod(String period) {
        if (String.isBlank(period) || !period.startsWith('FY')) return null;
        try {
            String yy = period.substring(2, 4);
            Integer yearNum = Integer.valueOf(yy);
            String suffix = period.substring(4);
            String priorYY = String.valueOf(yearNum - 1).leftPad(2, '0');
            return 'FY' + priorYY + suffix;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Extracts the full 4-digit fiscal year from a period token, e.g. 'FY26Q1' -> 2026.
     */
    @TestVisible
    private static Integer periodToYear(String period) {
        if (String.isBlank(period) || !period.startsWith('FY')) return null;
        try {
            return 2000 + Integer.valueOf(period.substring(2, 4));
        } catch (Exception e) {
            return null;
        }
    }
}
