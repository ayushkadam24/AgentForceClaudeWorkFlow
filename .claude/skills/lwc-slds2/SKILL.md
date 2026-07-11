---
name: lwc-slds2
description: LWC best practices (HTML, CSS, JS) and SLDS 2 styling rules for the vaccine scheduler UI. Used by dev-senior for LWCs and dev-mid for simple components; qa-engineer reads the accessibility section.
---

# LWC + SLDS 2 Best Practices

## Component design
- Small and single-purpose: vsSlotPicker, vsCheckInConsole, vsCertificateCard — compose, don't grow.
- Base lightning-* components FIRST (button, input, datatable, modal); hand-rolled HTML only when
  no base component fits. They ship accessibility and SLDS 2 compatibility for free.
- Data flow: @api down, CustomEvent up (composed:false by default; bubble deliberately).
  No two-way binding hacks; parent owns state, children render it.
- Wire adapters (@wire + getRecord/graphql) for reads; imperative Apex only for actions
  (book, cancel, check-in). One Apex controller per component family: VS_SlotPickerController.
- Errors: catch imperative-call failures, map message CODES (SLOT_FULL) to friendly copy,
  show via lightning-platform-show-toast-event or inline — never console.log-and-swallow, never raw stack traces to citizens.

## HTML
- Semantic first: real <button>, <ul>/<li> for lists — not clickable <div>s.
- lwc:if|elseif|else conditional blocks; for:each with a stable key (record Id, never index).
- Labels on every input (label attribute or slds-form-element pattern); helptext for anything ambiguous.

## JS
- getters for derived state, not fields recomputed in handlers; no logic in templates.
- Debounce user-driven searches (~300ms); disable action buttons while a call is in flight
  (prevents the double-submit that fights our slot-integrity story client-side).
- No @track needed for primitives (reactive by default); use spread to replace objects/arrays so reactivity fires.
- Labels/strings via Custom Labels (Marathi/Hindi come later — RFP §5); no hardcoded copy.
- data-testid attributes on interactive elements — the QA skill depends on them.

## CSS + SLDS 2 (org runs the Cosmos/SLDS 2 direction — future-proof from day one)
- Style with GLOBAL styling hooks: var(--slds-g-color-*, --slds-g-spacing-*, --slds-g-radius-*, --slds-g-font-*).
  SLDS 2 replaces design tokens ($tokens) entirely — never use them in new code.
- Do NOT: hardcode hex/px for themeable properties; override base-component internals by reaching
  into their markup (breaks on every release and under Cosmos); use deprecated --lwc-* tokens or
  component-level --slds-c-* hooks (not supported in SLDS 2).
- SLDS utility classes (slds-grid, slds-var-m-around_medium, slds-visually-hidden…) before custom CSS;
  custom CSS only for what utilities can't express.
- Run slds-linter over components before review packet; fix, don't suppress.

## Accessibility (Annexure C6 — WCAG 2.1 AA, testable)
- Full keyboard path: tab order logical, Enter/Space activate, focus VISIBLE (never outline:none
  without replacement), focus trapped in modals and returned on close.
- Slot availability: text + label, never color alone (C6.3). aria-live="polite" region announces
  slot search results and booking confirmation for screen readers.
- Touch targets ≥44px (P4 "one thumb" on a shared tablet); layout survives 200% zoom (no fixed heights clipping text).
- Every image/icon: alt text or aria-hidden if decorative.

## Mobile/3G reality (P1 citizens)
- Lazy-load below-the-fold; no heavy libraries for what platform provides; paginate slot lists.
- Loading states (lightning-spinner + skeleton) for every network wait; optimistic UI never
  for booking (the org's answer is the truth — show confirmed only after the service returns).
