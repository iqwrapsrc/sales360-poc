/**
 * @description  Orchestrates data retrieval from Data Cloud for the Portfolio and Spotlight panels.
 *               Queries DMOs via direct SOQL and Calculated Insights via ConnectApi.CdpQuery.
 *               Returns structured data ready for JSON serialization and Prompt Template input.
 *
 *               NOTE: Field API names below assume Phase 5 DMO/CI naming. If your DMO field
 *               names differ, update the SOQL/SQL strings accordingly.
 *
 * @author       Anup Chandran (Emirates Group IT)
 * @phase        Sales360 PoC - Phase 7
 * @since        May 2026
 */
public with sharing class Sales360DataService {

    @TestVisible
    private static final Integer PORTFOLIO_AGENCY_LIMIT = 20;

    @TestVisible
    private static final Integer SPOTLIGHT_OD_PAIR_LIMIT = 6;

    /**
     * Fetches the top 20 agencies for the given owner, joined with aggregate metrics from
     * 3 Calculated Insights (Flown Revenue, Flown PAX, Target Attainment).
     *
     * @param ownerUserId    The owner user ID (mapped via UserMappingService)
     * @param fiscalPeriod   E.g., 'FY26Q1'
     * @return               List of agency data maps, ready for JSON serialization
     */
    public static List<Map<String, Object>> getAgencyPortfolioData(
            String ownerUserId, String fiscalPeriod) {

        // Step 1: Query agency master from DMO via SOQL
        List<SObject> agencies = Database.query(
            'SELECT agency_id__c, agency_name__c, city__c, country__c, ' +
            'incentives_achieved__c, incentives_total__c ' +
            'FROM Agency__dlm ' +
            'WHERE owner_user_id__c = :ownerUserId ' +
            'LIMIT ' + PORTFOLIO_AGENCY_LIMIT
        );

        if (agencies.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        // Step 2: Build set of agency IDs for CIO filtering
        Set<String> agencyIds = new Set<String>();
        for (SObject a : agencies) {
            agencyIds.add((String) a.get('agency_id__c'));
        }

        // Step 3: Query CIOs via ConnectApi.CdpQuery
        Map<String, String> periodParts = parseFiscalPeriod(fiscalPeriod);
        Map<String, Decimal> revenueMap =
            queryCI(agencyIds, periodParts,
                    'Flown_Revenue_By_Agency__cio', 'flown_revenue_aed__c');
        Map<String, Decimal> paxMap =
            queryCI(agencyIds, periodParts,
                    'Flown_PAX_By_Agency__cio', 'flown_pax__c');
        Map<String, Decimal> attainmentMap =
            queryCI(agencyIds, periodParts,
                    'FY_Target_Attainment_By_Agency__cio', 'target_attainment_ratio__c');

        // Step 4: Join master with CI aggregates in memory
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (SObject a : agencies) {
            String agencyId = (String) a.get('agency_id__c');
            result.add(new Map<String, Object>{
                'agency_id'              => agencyId,
                'agency_name'            => (String) a.get('agency_name__c'),
                'city'                   => (String) a.get('city__c'),
                'country'                => (String) a.get('country__c'),
                'flown_revenue'          => revenueMap.get(agencyId),
                'flown_pax'              => paxMap.get(agencyId),
                'target_attainment_ratio'=> attainmentMap.get(agencyId),
                'incentives_achieved'    => a.get('incentives_achieved__c'),
                'incentives_total'       => a.get('incentives_total__c')
            });
        }
        return result;
    }

    /**
     * Fetches the top 6 OD pairs for opportunity spotlight, joined with market share CI data.
     */
    public static List<Map<String, Object>> getOpportunitySpotlightData(
            String ownerUserId, String fiscalPeriod) {

        // Query OD pairs that the owner's agencies operate on
        // (For PoC: just query top 6 OD pairs by criticality from the OD_Pair__dlm)
        List<SObject> odPairs = Database.query(
            'SELECT od_pair_id__c, region_pair__c, primary_airport__c, ' +
            'secondary_airport__c, route_count__c ' +
            'FROM OD_Pair__dlm ' +
            'LIMIT ' + SPOTLIGHT_OD_PAIR_LIMIT
        );

        if (odPairs.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        // Query market share CI (joined and structured for Prompt Template input)
        // Detailed implementation: query EK_Market_Share_By_OD_Pair__cio for these od_pair_ids
        // Build comprehensive od_pair_id-keyed map with EK share, competitor 1/2 data, forecasts
        // For brevity, this skeleton returns the OD pair master + placeholder for CI data

        Set<String> odPairIds = new Set<String>();
        for (SObject p : odPairs) {
            odPairIds.add((String) p.get('od_pair_id__c'));
        }

        // Build result list - in production code, join with market share CI data here
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (SObject p : odPairs) {
            result.add(new Map<String, Object>{
                'od_pair_id'      => (String) p.get('od_pair_id__c'),
                'region_pair'     => (String) p.get('region_pair__c'),
                'primary_airport' => (String) p.get('primary_airport__c'),
                'secondary_airport' => (String) p.get('secondary_airport__c'),
                'route_count'     => p.get('route_count__c')
                // Additional fields from market share CI populated here
            });
        }
        return result;
    }

    /**
     * Queries a CI via ConnectApi.CdpQuery and returns a Map of agencyId to value.
     */
    @TestVisible
    private static Map<String, Decimal> queryCI(Set<String> agencyIds,
                                                  Map<String, String> periodParts,
                                                  String ciName, String valueField) {
        String inClause = '\'' + String.join(new List<String>(agencyIds), '\',\'') + '\'';

        String sql = 'SELECT agency_id__c, ' + valueField + ' '
                   + 'FROM ' + ciName + ' '
                   + 'WHERE agency_id__c IN (' + inClause + ') '
                   + 'AND fiscal_year__c = \'' + periodParts.get('year') + '\' '
                   + 'AND fiscal_quarter__c = \'' + periodParts.get('quarter') + '\'';

        ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
        input.sql = sql;

        Map<String, Decimal> result = new Map<String, Decimal>();
        try {
            ConnectApi.CdpQueryOutput output = ConnectApi.CdpQuery.queryAnsiSql(input);
            if (output != null && output.data != null) {
                for (Object row : output.data) {
                    Map<String, Object> rowMap = (Map<String, Object>) row;
                    String agencyId = (String) rowMap.get('agency_id__c');
                    Decimal value = toDecimal(rowMap.get(valueField));
                    if (String.isNotBlank(agencyId)) {
                        result.put(agencyId, value);
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'CdpQuery failed for ' + ciName + ': ' + e.getMessage());
        }
        return result;
    }

    @TestVisible
    private static Map<String, String> parseFiscalPeriod(String fiscalPeriod) {
        Map<String, String> parts = new Map<String, String>();
        if (String.isBlank(fiscalPeriod) || fiscalPeriod.length() < 6) {
            parts.put('year', '2026');
            parts.put('quarter', '1');
            return parts;
        }
        // FY26Q1 => year=2026, quarter=1
        String year = '20' + fiscalPeriod.substring(2, 4);
        String quarter = fiscalPeriod.right(1);
        parts.put('year', year);
        parts.put('quarter', quarter);
        return parts;
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
