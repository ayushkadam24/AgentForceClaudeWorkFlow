/**
 * VS_SlotGenException — domain exception for the slot-generation engine (VS-06, EP-02).
 *
 * Thrown by VS_SlotGenerationService when a session cannot yield valid slots (invalid granularity,
 * invalid/degenerate time window). Message carries a short CODE (e.g. 'INVALID_GRANULARITY',
 * 'INVALID_WINDOW') that a caller/UI can map to friendly text — never a raw user-facing string
 * (rules/20, sf-apex-patterns "custom exceptions per domain with message CODES").
 *
 * Kept as a separate top-level class so VS_SlotGenBatch and VS_SlotGenerationService (and any later
 * slot-generation caller) share one exception type.
 *
 * Traceability: REQ-009/012/013/014, EP-02 / D-008, D-018, D-023.
 */
public class VS_SlotGenException extends Exception {}
