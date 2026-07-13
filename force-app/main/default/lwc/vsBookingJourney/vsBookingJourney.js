import { LightningElement } from 'lwc';
import VS_Tab_Book from '@salesforce/label/c.VS_Tab_Book';
import VS_Tab_Manage from '@salesforce/label/c.VS_Tab_Manage';

/**
 * vsBookingJourney — the citizen "one place for my vaccination appointments" shell: a Book tab
 * (vsSlotPicker) and a Manage tab (vsMyBookings). Composition over growth (lwc-slds2 skill): each child
 * stays small and single-purpose; this wrapper only owns the tab labels. Exposed to Experience Builder
 * (lightningCommunity) and Lightning app/home/record pages.
 */
export default class VsBookingJourney extends LightningElement {
    label = { VS_Tab_Book, VS_Tab_Manage };
}
