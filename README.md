# goose

[![Package Version](https://img.shields.io/hexpm/v/goose)](https://hex.pm/packages/goose)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/goose/)

A Gleam WebSocket consumer for AT Protocol Jetstream events.

```sh
gleam add goose@1
```

## Quick Start

```gleam
import goose
import gleam/io

pub fn main() {
  // Use default config with automatic retry logic
  let config = goose.default_config()

  goose.start_consumer(config, fn(json_event) {
    let event = goose.parse_event(json_event)

    case event {
      goose.CommitEvent(did, time_us, commit) -> {
        io.println("Commit: " <> commit.operation <> " in " <> commit.collection)
      }
      goose.IdentityEvent(did, time_us, identity) -> {
        io.println("Identity: " <> identity.handle)
      }
      goose.AccountEvent(did, time_us, account) -> {
        io.println("Account updated: " <> did)
      }
      goose.UnknownEvent(_) -> {
        io.println("Unknown event type")
      }
    }
  })
}
```

### Custom Configuration

```gleam
import goose
import gleam/option

pub fn main() {
  let config = goose.JetstreamConfig(
    endpoint: "wss://jetstream2.us-east.bsky.network/subscribe",
    wanted_collections: ["app.bsky.feed.post", "app.bsky.feed.like"],
    wanted_dids: [],
    cursor: option.None,
    max_message_size_bytes: option.None,
    compress: False,
    require_hello: False,
    // Retry configuration
    max_backoff_seconds: 60,      // Max wait between retries
    log_connection_events: True,  // Log connects/disconnects
    log_retry_attempts: False,    // Skip verbose retry logs
  )

  goose.start_consumer(config, handle_event)
}
```

## Configuration Options

**Note:** Goose automatically handles connection failures with exponential backoff retry logic (1s, 2s, 4s, 8s, 16s, 32s, up to max). All connections automatically retry on failure, reconnect on disconnection, and distinguish between harmless timeouts and real errors.

### `wanted_collections`
An array of Collection NSIDs to filter which records you receive (default: empty = all collections)

- Supports NSID path prefixes like `app.bsky.graph.*` or `app.bsky.*`
- The prefix before `.*` must pass NSID validation
- Incomplete prefixes like `app.bsky.graph.fo*` are not supported
- Account and Identity events are always received regardless of this filter
- Maximum 100 collections/prefixes

**Example:**
```gleam
wanted_collections: ["app.bsky.feed.post", "app.bsky.graph.*"]
```

### `wanted_dids`
An array of Repo DIDs to filter which records you receive (default: empty = all repos)

- Maximum 10,000 DIDs

**Example:**
```gleam
wanted_dids: ["did:plc:example123", "did:plc:example456"]
```

### `cursor`
A unix microseconds timestamp to begin playback from

- Absent cursor or future timestamp results in live-tail operation
- When reconnecting, use `time_us` from your most recently processed event
- Consider subtracting a few seconds as a buffer to ensure gapless playback

**Example:**
```gleam
cursor: option.Some(1234567890123456)
```

### `max_message_size_bytes`
The maximum size of a payload that this client would like to receive

- Zero means no limit
- Negative values are treated as zero
- Default: 0 (no maximum size)

**Example:**
```gleam
max_message_size_bytes: option.Some(1048576)  // 1MB limit
```

### `compress`
Enable zstd compression for WebSocket frames

- Set to `True` to enable compression
- Default: `False`
- Uses zstandard compression with Jetstream's custom dictionary
- Reduces bandwidth by approximately 50%
- Messages are automatically decompressed before reaching your callback
- Requires the `ezstd` library (automatically handled as a dependency)

**Example:**
```gleam
compress: True
```

**Note:** Compression is transparent to your application - compressed messages are automatically decompressed before being passed to your event handler. The bandwidth savings occur on the wire between the server and your client.

### `require_hello`
Pause replay/live-tail until server receives a `SubscriberOptionsUpdatePayload`

- Set to `True` to require initial handshake
- Default: `False`

**Example:**
```gleam
require_hello: True
```

### `max_backoff_seconds`
Maximum wait time in seconds between retry attempts

- Uses exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, then capped at this value
- Default: `60`

**Example:**
```gleam
max_backoff_seconds: 120  // Allow up to 2 minute waits between retries
```

### `log_connection_events`
Whether to log connection state changes (connected, disconnected)

- Set to `True` to log important connection events
- Default: `True`
- Recommended: `True` for production (know when disconnects happen)

**Example:**
```gleam
log_connection_events: True
```

### `log_retry_attempts`
Whether to log detailed retry attempt information

- Set to `True` to log attempt numbers, errors, and backoff times
- Default: `True`
- Recommended: `False` for production (reduces log noise)

**Example:**
```gleam
log_retry_attempts: False  // Production: skip verbose retry logs
```

## Full Configuration Example

```gleam
import goose
import gleam/option

let config = goose.JetstreamConfig(
  endpoint: "wss://jetstream2.us-east.bsky.network/subscribe",
  wanted_collections: ["app.bsky.feed.post", "app.bsky.graph.*"],
  wanted_dids: ["did:plc:example123"],
  cursor: option.Some(1234567890123456),
  max_message_size_bytes: option.Some(2097152),  // 2MB
  compress: True,
  require_hello: False,
  max_backoff_seconds: 60,
  log_connection_events: True,
  log_retry_attempts: False,
)

goose.start_consumer(config, handle_event)
```

Further documentation can be found at <https://hexdocs.pm/goose>.

## Development

```sh
gleam build # Build the project
gleam test  # Run the tests
```
