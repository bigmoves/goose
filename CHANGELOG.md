# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
