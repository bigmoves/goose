# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-11-04

### Changed
- **BREAKING**: Migrated from Erlang's `gun` library to Gleam's `stratus` WebSocket client
- **BREAKING**: Removed three configuration fields from `JetstreamConfig`:
  - `max_backoff_seconds` (retry logic still works internally, capped at 60s)
  - `log_connection_events` (connection logging removed)
  - `log_retry_attempts` (retry logging removed)
- Reduced Erlang FFI code from ~290 lines to ~40 lines
- Improved code maintainability with more idiomatic Gleam implementation

### Added
- Vendored `stratus` WebSocket client internally (moved to `goose/stratus`) until a new version is published
- New dependency: `simplifile` (>= 2.0.0 and < 3.0.0)
- New dependencies (from stratus): `gleam_otp`, `gleam_crypto`, `logging`, `exception`, `gramps`

### Removed
- Dependency: `gun` (>= 2.2.0 and < 3.0.0)

### Migration Guide
If you're upgrading from v1.x, remove the following fields from your `JetstreamConfig`:
```gleam
// Before (v1.x)
let config = goose.JetstreamConfig(
  endpoint: "wss://jetstream2.us-east.bsky.network/subscribe",
  wanted_collections: [],
  wanted_dids: [],
  cursor: option.None,
  max_message_size_bytes: option.None,
  compress: True,
  require_hello: False,
  max_backoff_seconds: 60,        // Remove this
  log_connection_events: True,    // Remove this
  log_retry_attempts: True,       // Remove this
)

// After (v2.x)
let config = goose.JetstreamConfig(
  endpoint: "wss://jetstream2.us-east.bsky.network/subscribe",
  wanted_collections: [],
  wanted_dids: [],
  cursor: option.None,
  max_message_size_bytes: option.None,
  compress: True,
  require_hello: False,
)
```

All other functionality remains the same. Automatic retry with exponential backoff still works internally.

## [1.1.0] - 2025-01-29

### Added
- Automatic retry logic with exponential backoff for all connections
- Three new configuration fields in `JetstreamConfig`:
  - `max_backoff_seconds: Int` - Maximum wait time between retries (default: 60)
  - `log_connection_events: Bool` - Log connection state changes (default: True)
  - `log_retry_attempts: Bool` - Log detailed retry information (default: True)

### Changed
- `start_consumer()` now automatically retries failed connections and handles disconnections
- Enhanced error handling distinguishes between harmless timeouts and real connection failures

### Fixed
- Connection failures no longer cause application to stop
- Harmless 60-second timeouts no longer trigger unnecessary reconnections
- WebSocket disconnections are handled gracefully with automatic reconnection

## [1.0.0] - 2024-10-28

### Added
- Initial release
- WebSocket consumer for AT Protocol Jetstream events
- Support for collection and DID filtering
- Zstd compression support
- Cursor-based replay
- Event parsing for Commit, Identity, and Account events
