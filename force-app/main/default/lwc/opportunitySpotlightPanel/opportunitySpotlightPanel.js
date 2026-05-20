import { LightningElement, track, api } from 'lwc';
import getSpotlightJson from '@salesforce/apex/Sales360SpotlightController.getSpotlightJson';
import refreshSpotlight from '@salesforce/apex/Sales360SpotlightController.refreshSpotlight';

/**
 * AI Opportunity Spotlight Panel
 *
 * Loading UX: imperative Apex, first call DEFERRED out of connectedCallback (microtask)
 * so the platform does not show its page-level overlay during initial render. Each panel
 * loads independently with its own slim progress bar; the rest of the page stays interactive.
 *
 * @author Anup Chandran - Sales360 PoC Phase 7
 */
export default class OpportunitySpotlightPanel extends LightningElement {

    @api
    get persona() { return this._persona; }
    set persona(value) {
        this._persona = value;
        if (this._connected) this.deferLoad();
    }
    _persona = '';

    @track fiscalPeriod = '';
    @track spotlightData = null;
    @track isLoading = true;
    @track error = null;

    _connected = false;
    _periodHandler;
    _personaHandler;

    connectedCallback() {
        this._connected = true;
        this._periodHandler = (e) => {
            this.fiscalPeriod = e.detail.fiscalPeriod;
            this.deferLoad();
        };
        this._personaHandler = (e) => {
            this._persona = e.detail.persona;
            this.deferLoad();
        };
        window.addEventListener('s360-period-change', this._periodHandler);
        window.addEventListener('s360-persona-change', this._personaHandler);

        if (!this.fiscalPeriod) {
            this.fiscalPeriod = this.computeCurrentPeriod();
        }
        this.deferLoad();
    }

    disconnectedCallback() {
        window.removeEventListener('s360-period-change', this._periodHandler);
        window.removeEventListener('s360-persona-change', this._personaHandler);
    }

    deferLoad() {
        this.isLoading = true;
        Promise.resolve().then(() => this.loadData());
    }

    async loadData() {
        this.isLoading = true;
        this.error = null;
        try {
            const raw = await getSpotlightJson({
                userId: this._persona,
                fiscalPeriod: this.fiscalPeriod
            });
            this.applyResult(raw);
        } catch (e) {
            this.error = 'Failed to load spotlights: ' + this.msg(e);
        } finally {
            this.isLoading = false;
        }
    }

    async handleRefresh() {
        this.isLoading = true;
        this.error = null;
        try {
            const raw = await refreshSpotlight({
                userId: this._persona,
                fiscalPeriod: this.fiscalPeriod
            });
            this.applyResult(raw);
        } catch (e) {
            this.error = 'Refresh failed: ' + this.msg(e);
        } finally {
            this.isLoading = false;
        }
    }

    applyResult(raw) {
        try {
            this.spotlightData = JSON.parse(raw);
            this.error = this.spotlightData.error ? this.spotlightData.error.message : null;
        } catch (e) {
            this.error = 'Unable to parse spotlight data';
        }
    }

    msg(e) {
        return (e && e.body && e.body.message) ? e.body.message
             : (e && e.message) ? e.message : 'Unknown error';
    }

    get hasData() {
        return this.spotlightData
            && this.spotlightData.spotlights
            && this.spotlightData.spotlights.length > 0;
    }

    get isEmpty() {
        return !this.isLoading
            && this.spotlightData
            && this.spotlightData.spotlights
            && this.spotlightData.spotlights.length === 0;
    }

    get hasError() {
        return !this.isLoading && !!this.error;
    }

    get headlineNarrative() {
        return this.spotlightData && this.spotlightData.summary
            ? this.spotlightData.summary.headlineNarrative : '';
    }

    get totalOpportunities() {
        // Derive from the actual spotlights array so ROUTES is always populated,
        // regardless of whether the LLM filled summary.totalOpportunitiesCovered.
        if (this.spotlightData && this.spotlightData.spotlights) {
            return this.spotlightData.spotlights.length;
        }
        return 0;
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

    computeCurrentPeriod() {
        const now = new Date();
        const year = now.getFullYear();
        const month = now.getMonth() + 1;
        const quarter = Math.floor((month - 1) / 3) + 1;
        return `FY${String(year).slice(-2)}Q${quarter}`;
    }
}
