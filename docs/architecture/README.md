# Architecture

Features use domain, application, infrastructure, and presentation boundaries.
Authoritative arithmetic belongs to pure Dart domain services. Local AI can only
create schema-validated proposals; approved application commands perform writes.

Stable seams are `LocalAgent`, `RecipeOcr`, `ForecastEngine`, `InventoryLedger`,
`ApprovalService`, and `BackupService`. Persistence will use Drift over encrypted
native SQLite, with quantities as scaled integers and ratios as integer pairs.
