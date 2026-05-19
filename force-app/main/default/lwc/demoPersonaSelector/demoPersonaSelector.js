import { LightningElement, wire, track } from 'lwc';
import getAvailablePersonas from '@salesforce/apex/UserMappingService.getAvailablePersonas';

/**
 * Demo Persona Selector (Optional)
 *
 * Dropdown that allows switching between test personas during a demo.
 * Reads personas from UserMappingService and emits 's360-persona-change' event
 * that all Sales360 panels listen for.
 *
 * @author Anup Chandran - Sales360 PoC Phase 7
 */
export default class DemoPersonaSelector extends LightningElement {

    @track selectedPersona = '';
    @track personaOptions = [];
    @track error = null;

    @wire(getAvailablePersonas)
    wiredPersonas({ data, error }) {
        if (data) {
            this.personaOptions = data.map(p => ({
                label: p.label,
                value: p.value
            }));
            // Default to first persona
            if (this.personaOptions.length > 0 && !this.selectedPersona) {
                this.selectedPersona = this.personaOptions[0].value;
            }
        } else if (error) {
            this.error = 'Failed to load personas';
        }
    }

    handleChange(event) {
        const newPersona = event.detail.value;
        this.selectedPersona = newPersona;

        // Emit window event so all peer LWCs can react
        window.dispatchEvent(new CustomEvent('s360-persona-change', {
            detail: { persona: newPersona }
        }));

        // Also fire as component event
        this.dispatchEvent(new CustomEvent('personachange', {
            detail: { persona: newPersona }
        }));
    }

    get hasError() {
        return !!this.error;
    }

    get hasPersonas() {
        return this.personaOptions.length > 0;
    }
}
