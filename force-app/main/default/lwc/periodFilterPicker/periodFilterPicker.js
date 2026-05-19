import { LightningElement, api, track } from 'lwc';

/**
 * Period Filter Picker
 *
 * A focused dropdown LWC for selecting fiscal period. Emits a window-level
 * 's360-period-change' event that all Sales360 panels listen for.
 *
 * Hosted within the My Performance KPI Bar header but can also be used standalone.
 *
 * @author Anup Chandran - Sales360 PoC Phase 7
 */
export default class PeriodFilterPicker extends LightningElement {

    @api selectedPeriod = '';
    @track _selected = '';

    connectedCallback() {
        // Default to current quarter if no selection provided
        if (!this.selectedPeriod) {
            this._selected = this.computeCurrentPeriod();
        } else {
            this._selected = this.selectedPeriod;
        }
    }

    get periodOptions() {
        return [
            { label: 'FY26 Q1',                value: 'FY26Q1' },
            { label: 'FY26 Q2',                value: 'FY26Q2' },
            { label: 'FY26 Q3',                value: 'FY26Q3' },
            { label: 'FY26 Q4',                value: 'FY26Q4' },
            { label: 'FY26 Full Year',         value: 'FY26' },
            { label: 'Last 12 Months',         value: 'LAST12MONTHS' },
            { label: 'FY25 Q1 (Prior Year)',   value: 'FY25Q1' }
        ];
    }

    get value() {
        return this._selected;
    }

    handleChange(event) {
        const newPeriod = event.detail.value;
        this._selected = newPeriod;

        // Emit window event so all peer LWCs can react
        window.dispatchEvent(new CustomEvent('s360-period-change', {
            detail: { fiscalPeriod: newPeriod }
        }));

        // Also dispatch as standard component event for direct parent listening
        this.dispatchEvent(new CustomEvent('periodchange', {
            detail: { fiscalPeriod: newPeriod }
        }));
    }

    computeCurrentPeriod() {
        const now = new Date();
        const year = now.getFullYear();
        const month = now.getMonth() + 1;
        const quarter = Math.floor((month - 1) / 3) + 1;
        const yearShort = String(year).slice(-2);
        return `FY${yearShort}Q${quarter}`;
    }
}
