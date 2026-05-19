import { LightningElement, wire, track, api } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getMyPerformanceKpis from '@salesforce/apex/Sales360KpiController.getMyPerformanceKpis';
import refreshMyPerformanceKpis from '@salesforce/apex/Sales360KpiController.refreshMyPerformanceKpis';

/**
 * My Performance KPI Bar
 *
 * Top-of-page KPI strip showing 4 high-impact KPIs:
 * - Flown Revenue
 * - Flown PAX
 * - Forward Revenue
 * - Forward PAX
 *
 * Each card shows current value + YoY trend.
 * Fast path (no LLM) - loads in 1-2 seconds.
 *
 * @author Anup Chandran - Sales360 PoC Phase 7
 */
export default class MyPerformanceKpiBar extends LightningElement {

    @api persona = '';
    @track fiscalPeriod = '';
    @track kpiData = null;
    @track isRefreshing = false;
    @track error = null;

    wiredResult;
    _periodHandler;
    _personaHandler;

    connectedCallback() {
        this._periodHandler = (e) => { this.fiscalPeriod = e.detail.fiscalPeriod; };
        this._personaHandler = (e) => { this.persona = e.detail.persona; };
        window.addEventListener('s360-period-change', this._periodHandler);
        window.addEventListener('s360-persona-change', this._personaHandler);

        // Initialize default period if not provided
        if (!this.fiscalPeriod) {
            this.fiscalPeriod = this.computeCurrentPeriod();
        }
    }

    disconnectedCallback() {
        window.removeEventListener('s360-period-change', this._periodHandler);
        window.removeEventListener('s360-persona-change', this._personaHandler);
    }

    @wire(getMyPerformanceKpis, { userId: '$persona', fiscalPeriod: '$fiscalPeriod' })
    wiredKpis(result) {
        this.wiredResult = result;
        if (result.data) {
            try {
                this.kpiData = JSON.parse(result.data);
                this.error = null;
            } catch (e) {
                this.error = 'Unable to parse KPI data';
            }
        } else if (result.error) {
            const message = result.error.body
                ? result.error.body.message
                : result.error.message;
            this.error = 'Failed to load KPIs: ' + message;
        }
    }

    get kpis() {
        if (!this.kpiData || !this.kpiData.kpis) return [];
        return this.kpiData.kpis.map(k => ({
            ...k,
            trendClass: 'kpi-trend-' + (k.trend || 'flat').toLowerCase(),
            cardClass: 'kpi-card kpi-card-' + k.kpiId.toLowerCase().replace(/_/g, '-'),
            trendUp: k.trend === 'UP',
            trendDown: k.trend === 'DOWN',
            trendFlat: k.trend === 'FLAT'
        }));
    }

    get fiscalPeriodLabel() {
        if (!this.fiscalPeriod) return '';
        if (this.fiscalPeriod.includes('Q')) {
            return this.fiscalPeriod.replace(/Q/, ' Q');
        }
        if (this.fiscalPeriod === 'LAST12MONTHS') {
            return 'Last 12 Months';
        }
        return this.fiscalPeriod;
    }

    get hasError() {
        return !!this.error;
    }

    async handleRefresh() {
        this.isRefreshing = true;
        try {
            await refreshMyPerformanceKpis({
                userId: this.persona,
                fiscalPeriod: this.fiscalPeriod
            });
            await refreshApex(this.wiredResult);
        } catch (e) {
            this.error = 'Refresh failed: ' + e.message;
        } finally {
            this.isRefreshing = false;
        }
    }

    computeCurrentPeriod() {
        const now = new Date();
        const year = now.getFullYear();
        const month = now.getMonth() + 1;
        const quarter = Math.floor((month - 1) / 3) + 1;
        return `FY${String(year).slice(-2)}Q${quarter}`;
    }
}
