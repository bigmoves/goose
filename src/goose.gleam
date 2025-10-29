import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// Jetstream event types
pub type JetstreamEvent {
  CommitEvent(did: String, time_us: Int, commit: CommitData)
  IdentityEvent(did: String, time_us: Int, identity: IdentityData)
  AccountEvent(did: String, time_us: Int, account: AccountData)
  UnknownEvent(raw: String)
}

pub type CommitData {
  CommitData(
    rev: String,
    operation: String,
    collection: String,
    rkey: String,
    record: Option(Dynamic),
    cid: Option(String),
  )
}

pub type IdentityData {
  IdentityData(did: String, handle: String, seq: Int, time: String)
}

pub type AccountData {
  AccountData(active: Bool, did: String, seq: Int, time: String)
}

/// Configuration for Jetstream consumer
pub type JetstreamConfig {
  JetstreamConfig(
    endpoint: String,
    wanted_collections: List(String),
    wanted_dids: List(String),
    cursor: Option(Int),
    max_message_size_bytes: Option(Int),
    compress: Bool,
    require_hello: Bool,
    /// Maximum backoff time in seconds for retry logic (default: 60)
    max_backoff_seconds: Int,
    /// Whether to log connection events (connected, disconnected) (default: True)
    log_connection_events: Bool,
    /// Whether to log retry attempts and errors (default: True)
    log_retry_attempts: Bool,
  )
}

/// Create a default configuration for US East endpoint
/// Includes automatic retry with exponential backoff (1s, 2s, 4s, 8s, 16s, 32s, capped at 60s)
pub fn default_config() -> JetstreamConfig {
  JetstreamConfig(
    endpoint: "wss://jetstream2.us-east.bsky.network/subscribe",
    wanted_collections: [],
    wanted_dids: [],
    cursor: option.None,
    max_message_size_bytes: option.None,
    compress: False,
    require_hello: False,
    max_backoff_seconds: 60,
    log_connection_events: True,
    log_retry_attempts: True,
  )
}

/// Build the WebSocket URL with query parameters
pub fn build_url(config: JetstreamConfig) -> String {
  let base = config.endpoint
  let mut_params = []

  // Add wanted collections (each as a separate query parameter)
  let mut_params = case config.wanted_collections {
    [] -> mut_params
    collections -> {
      let collection_params =
        list.map(collections, fn(col) { "wantedCollections=" <> col })
      list.append(collection_params, mut_params)
    }
  }

  // Add wanted DIDs (each as a separate query parameter)
  let mut_params = case config.wanted_dids {
    [] -> mut_params
    dids -> {
      let did_params = list.map(dids, fn(did) { "wantedDids=" <> did })
      list.append(did_params, mut_params)
    }
  }

  // Add cursor if specified
  let mut_params = case config.cursor {
    option.None -> mut_params
    option.Some(cursor_val) ->
      list.append(["cursor=" <> string.inspect(cursor_val)], mut_params)
  }

  // Add maxMessageSizeBytes if specified
  let mut_params = case config.max_message_size_bytes {
    option.None -> mut_params
    option.Some(size_val) ->
      list.append(
        ["maxMessageSizeBytes=" <> string.inspect(size_val)],
        mut_params,
      )
  }

  // Add compress parameter (always include it)
  let mut_params = case config.compress {
    False -> list.append(["compress=false"], mut_params)
    True -> list.append(["compress=true"], mut_params)
  }

  // Add requireHello parameter (always include it)
  let mut_params = case config.require_hello {
    False -> list.append(["requireHello=false"], mut_params)
    True -> list.append(["requireHello=true"], mut_params)
  }

  case mut_params {
    [] -> base
    params -> base <> "?" <> string.join(list.reverse(params), "&")
  }
}

/// Connect to Jetstream WebSocket using Erlang gun library
@external(erlang, "goose_ws_ffi", "connect")
pub fn connect(
  url: String,
  handler_pid: Pid,
  compress: Bool,
) -> Result(Pid, Dynamic)

/// Start consuming the Jetstream feed with automatic retry logic
///
/// Handles connection failures gracefully with exponential backoff and automatic reconnection.
/// The retry behavior is configured through the JetstreamConfig fields:
/// - max_backoff_seconds: Maximum wait time between retries
/// - log_connection_events: Log connects/disconnects
/// - log_retry_attempts: Log retry attempts and errors
///
/// Example:
/// ```gleam
/// let config = goose.default_config()
///
/// goose.start_consumer(config, fn(event_json) {
///   // Handle event
///   io.println(event_json)
/// })
/// ```
pub fn start_consumer(
  config: JetstreamConfig,
  on_event: fn(String) -> Nil,
) -> Nil {
  start_with_retry_internal(config, on_event, 0)
}

/// Internal function to handle connection with retry
fn start_with_retry_internal(
  config: JetstreamConfig,
  on_event: fn(String) -> Nil,
  retry_count: Int,
) -> Nil {
  let url = build_url(config)
  let self = process.self()
  let result = connect(url, self, config.compress)

  case result {
    Ok(_conn_pid) -> {
      case config.log_connection_events {
        True -> io.println("Connected to Jetstream successfully")
        False -> Nil
      }
      // Start receiving with retry support
      receive_with_retry(config, on_event)
    }
    Error(err) -> {
      // Connection failed, calculate backoff and retry
      let backoff_seconds = calculate_backoff(retry_count, config)
      case config.log_retry_attempts {
        True -> {
          io.println(
            "Failed to connect to Jetstream (attempt "
            <> int.to_string(retry_count + 1)
            <> "): "
            <> string.inspect(err),
          )
          io.println(
            "Retrying in " <> int.to_string(backoff_seconds) <> " seconds...",
          )
        }
        False -> Nil
      }

      // Sleep for backoff period
      process.sleep(backoff_seconds * 1000)

      // Retry connection
      start_with_retry_internal(config, on_event, retry_count + 1)
    }
  }
}

/// Calculate exponential backoff with configurable maximum
fn calculate_backoff(retry_count: Int, config: JetstreamConfig) -> Int {
  let backoff = case retry_count {
    0 -> 1
    1 -> 2
    2 -> 4
    3 -> 8
    4 -> 16
    5 -> 32
    _ -> config.max_backoff_seconds
  }

  // Cap at max_backoff_seconds
  case backoff > config.max_backoff_seconds {
    True -> config.max_backoff_seconds
    False -> backoff
  }
}

/// Receive messages with retry logic
fn receive_with_retry(
  config: JetstreamConfig,
  on_event: fn(String) -> Nil,
) -> Nil {
  case receive_ws_message() {
    Ok(text) -> {
      on_event(text)
      receive_with_retry(config, on_event)
    }
    Error(error_dynamic) -> {
      // Decode error type
      let atm = atom.cast_from_dynamic(error_dynamic)
      let error_type = atom.to_string(atm)

      case error_type {
        "timeout" -> {
          // No messages in 60s, connection is alive - continue
          receive_with_retry(config, on_event)
        }
        "closed" -> {
          // Connection closed - log if configured
          case config.log_connection_events {
            True -> io.println("Jetstream connection closed, reconnecting...")
            False -> Nil
          }
          start_with_retry_internal(config, on_event, 0)
        }
        "connection_error" -> {
          // Connection error - log if configured
          case config.log_connection_events {
            True -> io.println("Jetstream connection error, reconnecting...")
            False -> Nil
          }
          start_with_retry_internal(config, on_event, 0)
        }
        _ -> {
          // Unknown error - log if retry logging is enabled
          case config.log_retry_attempts {
            True -> {
              io.println("Unknown Jetstream error: " <> error_type)
              io.println("Reconnecting...")
            }
            False -> Nil
          }
          start_with_retry_internal(config, on_event, 0)
        }
      }
    }
  }
}

/// Receive a WebSocket message from the message queue
/// Returns Ok(text) for messages, or Error with one of: timeout, closed, connection_error
@external(erlang, "goose_ffi", "receive_ws_message")
fn receive_ws_message() -> Result(String, Dynamic)

/// Parse a JSON event string into a JetstreamEvent
pub fn parse_event(json_string: String) -> JetstreamEvent {
  // Try to parse as commit event first
  case json.parse(json_string, commit_event_decoder()) {
    Ok(event) -> event
    Error(_) -> {
      // Try identity event
      case json.parse(json_string, identity_event_decoder()) {
        Ok(event) -> event
        Error(_) -> {
          // Try account event
          case json.parse(json_string, account_event_decoder()) {
            Ok(event) -> event
            Error(_) -> UnknownEvent(json_string)
          }
        }
      }
    }
  }
}

/// Decoder for commit events
fn commit_event_decoder() {
  use did <- decode.field("did", decode.string)
  use time_us <- decode.field("time_us", decode.int)
  use commit <- decode.field("commit", commit_data_decoder())
  decode.success(CommitEvent(did: did, time_us: time_us, commit: commit))
}

/// Decoder for commit data - handles both create/update (with record) and delete (without)
fn commit_data_decoder() {
  // Try decoder with record and cid fields first (for create/update)
  // If that fails, try without (for delete)
  decode.one_of(commit_with_record_decoder(), or: [
    commit_without_record_decoder(),
  ])
}

/// Decoder for commit with record (create/update operations)
fn commit_with_record_decoder() {
  use rev <- decode.field("rev", decode.string)
  use operation <- decode.field("operation", decode.string)
  use collection <- decode.field("collection", decode.string)
  use rkey <- decode.field("rkey", decode.string)
  use record <- decode.field("record", decode.dynamic)
  use cid <- decode.field("cid", decode.string)
  decode.success(CommitData(
    rev: rev,
    operation: operation,
    collection: collection,
    rkey: rkey,
    record: option.Some(record),
    cid: option.Some(cid),
  ))
}

/// Decoder for commit without record (delete operations)
fn commit_without_record_decoder() {
  use rev <- decode.field("rev", decode.string)
  use operation <- decode.field("operation", decode.string)
  use collection <- decode.field("collection", decode.string)
  use rkey <- decode.field("rkey", decode.string)
  decode.success(CommitData(
    rev: rev,
    operation: operation,
    collection: collection,
    rkey: rkey,
    record: option.None,
    cid: option.None,
  ))
}

/// Decoder for identity events
fn identity_event_decoder() {
  use did <- decode.field("did", decode.string)
  use time_us <- decode.field("time_us", decode.int)
  use identity <- decode.field("identity", identity_data_decoder())
  decode.success(IdentityEvent(did: did, time_us: time_us, identity: identity))
}

/// Decoder for identity data
fn identity_data_decoder() {
  use did <- decode.field("did", decode.string)
  use handle <- decode.field("handle", decode.string)
  use seq <- decode.field("seq", decode.int)
  use time <- decode.field("time", decode.string)
  decode.success(IdentityData(did: did, handle: handle, seq: seq, time: time))
}

/// Decoder for account events
fn account_event_decoder() {
  use did <- decode.field("did", decode.string)
  use time_us <- decode.field("time_us", decode.int)
  use account <- decode.field("account", account_data_decoder())
  decode.success(AccountEvent(did: did, time_us: time_us, account: account))
}

/// Decoder for account data
fn account_data_decoder() {
  use active <- decode.field("active", decode.bool)
  use did <- decode.field("did", decode.string)
  use seq <- decode.field("seq", decode.int)
  use time <- decode.field("time", decode.string)
  decode.success(AccountData(active: active, did: did, seq: seq, time: time))
}
