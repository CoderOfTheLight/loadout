# Threat model

Protected assets include item names, quantities, events, recipes, OCR text, prompts,
forecasts, and encryption keys. The MVP has no runtime network capability.

Primary threats are device loss, temporary images, prompt injection, malformed model
output, identifier invention, backup theft, content-bearing logs, and accidental
permissions. Required mitigations are encrypted persistence, typed allowlisted tools,
explicit confirmation, cleanup, encrypted exports, content-free diagnostics, and tests
asserting no Android internet permission.
