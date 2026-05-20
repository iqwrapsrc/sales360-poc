import { LightningElement, track, api } from 'lwc';
import getPortfolioJson from '@salesforce/apex/Sales360PortfolioController.getPortfolioJson';
import refreshPortfolio from '@salesforce/apex/Sales360PortfolioController.refreshPortfolio';

/**
 * Portfolio Summary Panel
 *
 * AI-powered agency portfolio panel.
 *
 * Loading UX: imperative Apex, but the first call is DEFERRED out of connectedCallback
 * (via Promise microtask) so Salesforce does NOT show its page-level loading overlay
 * during initial render. Each panel loads independently with its own slim progress bar;
 * the rest of the page stays fully interactive.
 *
 * @author Anup Chandran - Sales360 PoC Phase 7
 */
export default class PortfolioSummaryPanel extends LightningElement {

    @api
    get persona() { return this._persona; }
    set persona(value) {
        this._persona = value;
        if (this._connected) this.deferLoad();
    }
    _persona = '';

    @track fiscalPeriod = '';
    @track portfolio = null;
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
        // Defer initial load so the page finishes its first paint without the
        // platform throwing up a global loading overlay.
        this.deferLoad();
    }

    disconnectedCallback() {
        window.removeEventListener('s360-period-change', this._periodHandler);
        window.removeEventListener('s360-persona-change', this._personaHandler);
    }

    // Push the Apex call to a microtask so it runs AFTER the synchronous render cycle.
    deferLoad() {
        this.isLoading = true;
        Promise.resolve().then(() => this.loadData());
    }

    async loadData() {
        this.isLoading = true;
        this.error = null;
        try {
            const raw = await getPortfolioJson({
                userId: this._persona,
                fiscalPeriod: this.fiscalPeriod
            });
            this.applyResult(raw);
        } catch (e) {
            this.error = 'Failed to load portfolio: ' + this.msg(e);
        } finally {
            this.isLoading = false;
        }
    }

    async handleRefresh() {
        this.isLoading = true;
        this.error = null;
        try {
            const raw = await refreshPortfolio({
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
            this.portfolio = JSON.parse(raw);
            this.error = this.portfolio.error ? this.portfolio.error.message : null;
        } catch (e) {
            this.error = 'Unable to parse portfolio data';
        }
    }

    msg(e) {
        return (e && e.body && e.body.message) ? e.body.message
             : (e && e.message) ? e.message : 'Unknown error';
    }

    get hasData() {
        return this.portfolio
            && this.portfolio.agencies
            && this.portfolio.agencies.length > 0;
    }

    get isEmpty() {
        return !this.isLoading
            && this.portfolio
            && this.portfolio.agencies
            && this.portfolio.agencies.length === 0;
    }

    get hasError() {
        return !this.isLoading && !!this.error;
    }

    get headlineNarrative() {
        return this.portfolio && this.portfolio.summary
            ? this.portfolio.summary.headlineNarrative : '';
    }

    get totalAgencies() {
        // Derive from the actual agencies array so the tile is always populated,
        // regardless of whether the LLM filled summary.totalAgenciesCovered.
        if (this.portfolio && this.portfolio.agencies) {
            return this.portfolio.agencies.length;
        }
        return 0;
    }

    get redCount() {
        return this.portfolio && this.portfolio.summary
            ? this.portfolio.summary.redCount : 0;
    }

    get amberCount() {
        return this.portfolio && this.portfolio.summary
            ? this.portfolio.summary.amberCount : 0;
    }

    get greenCount() {
        return this.portfolio && this.portfolio.summary
            ? this.portfolio.summary.greenCount : 0;
    }

    get agencies() {
        if (!this.portfolio || !this.portfolio.agencies) return [];
        return this.portfolio.agencies.map(a => ({
            ...a,
            ragClass: 'agency-rag-' + (a.ragStatus || 'flat').toLowerCase(),
            ragLabel: a.ragStatus
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
