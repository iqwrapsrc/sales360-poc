import { LightningElement, wire, track, api } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getPortfolioJson from '@salesforce/apex/Sales360PortfolioController.getPortfolioJson';
import refreshPortfolio from '@salesforce/apex/Sales360PortfolioController.refreshPortfolio';

/**
 * Portfolio Summary Panel
 *
 * AI-powered panel showing the Sales Executive's agency portfolio.
 * Displays up to 20 agencies with RAG-coloured status, AI-generated narrative,
 * and key metrics (booked PAX, ticketed revenue, target attainment, incentives).
 *
 * @author Anup Chandran - Sales360 PoC Phase 7
 */
export default class PortfolioSummaryPanel extends LightningElement {

    @api persona = '';
    @track fiscalPeriod = '';
    @track portfolio = null;
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

    @wire(getPortfolioJson, { userId: '$persona', fiscalPeriod: '$fiscalPeriod' })
    wiredPortfolio(result) {
        this.wiredResult = result;
        if (result.data) {
            try {
                this.portfolio = JSON.parse(result.data);
                this.error = this.portfolio.error ? this.portfolio.error.message : null;
            } catch (e) {
                this.error = 'Unable to parse portfolio data';
            }
        } else if (result.error) {
            const message = result.error.body
                ? result.error.body.message
                : result.error.message;
            this.error = 'Failed to load portfolio: ' + message;
        }
    }

    get hasData() {
        return this.portfolio
            && this.portfolio.agencies
            && this.portfolio.agencies.length > 0;
    }

    get isEmpty() {
        return this.portfolio
            && this.portfolio.agencies
            && this.portfolio.agencies.length === 0;
    }

    get hasError() {
        return !!this.error;
    }

    get headlineNarrative() {
        return this.portfolio && this.portfolio.summary
            ? this.portfolio.summary.headlineNarrative : '';
    }

    get totalAgencies() {
        return this.portfolio && this.portfolio.summary
            ? this.portfolio.summary.totalAgenciesCovered : 0;
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

    async handleRefresh() {
        this.isRefreshing = true;
        try {
            await refreshPortfolio({
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
