import { LightningElement, wire, track, api } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getSpotlightJson from '@salesforce/apex/Sales360SpotlightController.getSpotlightJson';
import refreshSpotlight from '@salesforce/apex/Sales360SpotlightController.refreshSpotlight';

/**
 * AI Opportunity Spotlight Panel
 *
 * AI-powered panel showing the top 6 OD pair (route) opportunities requiring attention.
 * Each spotlight shows EK market share, competitor analysis, and forecasted seat factors.
 *
 * @author Anup Chandran - Sales360 PoC Phase 7
 */
export default class OpportunitySpotlightPanel extends LightningElement {

    @api persona = '';
    @track fiscalPeriod = '';
    @track spotlightData = null;
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

        if (!this.fiscalPeriod) {
            this.fiscalPeriod = this.computeCurrentPeriod();
        }
    }

    disconnectedCallback() {
        window.removeEventListener('s360-period-change', this._periodHandler);
        window.removeEventListener('s360-persona-change', this._personaHandler);
    }

    @wire(getSpotlightJson, { userId: '$persona', fiscalPeriod: '$fiscalPeriod' })
    wiredSpotlight(result) {
        this.wiredResult = result;
        if (result.data) {
            try {
                this.spotlightData = JSON.parse(result.data);
                this.error = this.spotlightData.error ? this.spotlightData.error.message : null;
            } catch (e) {
                this.error = 'Unable to parse spotlight data';
            }
        } else if (result.error) {
            const message = result.error.body
                ? result.error.body.message
                : result.error.message;
            this.error = 'Failed to load spotlights: ' + message;
        }
    }

    get hasData() {
        return this.spotlightData
            && this.spotlightData.spotlights
            && this.spotlightData.spotlights.length > 0;
    }

    get isEmpty() {
        return this.spotlightData
            && this.spotlightData.spotlights
            && this.spotlightData.spotlights.length === 0;
    }

    get hasError() {
        return !!this.error;
    }

    get headlineNarrative() {
        return this.spotlightData && this.spotlightData.summary
            ? this.spotlightData.summary.headlineNarrative : '';
    }

    get totalOpportunities() {
        return this.spotlightData && this.spotlightData.summary
            ? this.spotlightData.summary.totalOpportunitiesCovered : 0;
    }

    get redCount() {
        return this.spotlightData && this.spotlightData.summary
            ? this.spotlightData.summary.redCount : 0;
    }

    get amberCount() {
        return this.spotlightData && this.spotlightData.summary
            ? this.spotlightData.summary.amberCount : 0;
    }

    get greenCount() {
        return this.spotlightData && this.spotlightData.summary
            ? this.spotlightData.summary.greenCount : 0;
    }

    get spotlights() {
        if (!this.spotlightData || !this.spotlightData.spotlights) return [];
        return this.spotlightData.spotlights.map(s => ({
            ...s,
            ragClass: 'spotlight-rag-' + (s.ragStatus || 'flat').toLowerCase(),
            ragLabel: s.ragStatus,
            headerKpiLabel: s.metrics && s.metrics.headerKpi
                ? s.metrics.headerKpi.label : '',
            headerKpiValue: s.metrics && s.metrics.headerKpi
                ? s.metrics.headerKpi.value : ''
        }));
    }

    async handleRefresh() {
        this.isRefreshing = true;
        try {
            await refreshSpotlight({
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
