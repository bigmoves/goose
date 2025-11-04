import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http/request
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import goose/internal/zstd
import goose/stratus
import simplifile

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
  )
}

/// Internal state for WebSocket connection
type ConnectionState {
  ConnectionState(
    config: JetstreamConfig,
    on_event: fn(String) -> Nil,
    decompressor: Option(Decompressor),
  )
}

/// Decompression context holder
type Decompressor {
  Decompressor(dctx: zstd.DecompressionContext, ddict: zstd.DecompressionDict)
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

/// Load the zstd decompression dictionary
fn load_decompressor() -> Result(Decompressor, String) {
  // Get priv directory
  let priv_dir = get_priv_dir()
  let dict_path = priv_dir <> "/zstd_dictionary"

  // Read dictionary file
  use dict_data <- result.try(
    simplifile.read_bits(dict_path)
    |> result.map_error(fn(_) {
      "Failed to load zstd dictionary from " <> dict_path
    }),
  )

  // Create decompression context and dictionary
  let dctx = zstd.create_decompression_context(1024 * 1024)
  let ddict = zstd.create_ddict(dict_data)

  // Select dictionary for context
  use _ <- result.try(zstd.select_ddict(dctx, ddict))

  Ok(Decompressor(dctx: dctx, ddict: ddict))
}

/// Get the priv directory path for this application
@external(erlang, "goose_ffi", "priv_dir")
fn get_priv_dir() -> String

/// Decompress zstd-compressed data
fn decompress_data(
  data: BitArray,
  decompressor: Decompressor,
) -> Result(String, String) {
  // Try decompress_using_ddict first (works for frames with content size)
  case zstd.decompress_using_ddict(data, decompressor.ddict) {
    Ok(decompressed) ->
      bit_array.to_string(decompressed)
      |> result.replace_error("Failed to decode decompressed data as UTF-8")
    Error(msg) -> {
      // Check if error is due to unknown content size
      case string.contains(msg, "ZSTD_CONTENTSIZE_UNKNOWN") {
        True -> {
          // Frame doesn't have content size, use streaming with dictionary-loaded context
          case zstd.decompress_streaming(decompressor.dctx, data) {
            Ok(decompressed) ->
              bit_array.to_string(decompressed)
              |> result.replace_error(
                "Failed to decode streaming decompressed data as UTF-8",
              )
            Error(_stream_err) -> Error("Streaming decompression failed")
          }
        }
        False -> Error("Decompression failed")
      }
    }
  }
}

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

  // Convert wss:// to https:// and ws:// to http:// for request parsing
  let http_url =
    url
    |> string.replace("wss://", "https://")
    |> string.replace("ws://", "http://")

  // Parse URL into HTTP request
  let assert Ok(req) = request.to(http_url)

  // Load decompressor if compression is enabled
  let decompressor = case config.compress {
    True ->
      case load_decompressor() {
        Ok(dec) -> option.Some(dec)
        Error(_err) -> option.None
      }
    False -> option.None
  }

  // Create initial state
  let state =
    ConnectionState(
      config: config,
      on_event: on_event,
      decompressor: decompressor,
    )

  // Start WebSocket connection
  let result =
    stratus.new_with_initialiser(request: req, init: fn() {
      Ok(stratus.initialised(state))
    })
    |> stratus.on_message(handle_message)
    |> stratus.on_close(handle_close)
    |> stratus.with_connect_timeout(30_000)
    |> stratus.start()

  case result {
    Ok(_websocket) -> {
      // Keep process alive indefinitely
      process.sleep_forever()
    }
    Error(_err) -> {
      // Connection failed, calculate backoff and retry
      let backoff_seconds = calculate_backoff(retry_count)

      // Sleep for backoff period
      process.sleep(backoff_seconds * 1000)

      // Retry connection
      start_with_retry_internal(config, on_event, retry_count + 1)
    }
  }
}

/// Handle incoming WebSocket messages
fn handle_message(
  state: ConnectionState,
  msg: stratus.Message(Nil),
  _conn: stratus.Connection,
) -> stratus.Next(ConnectionState, Nil) {
  case msg {
    stratus.Text(text) -> {
      state.on_event(text)
      stratus.continue(state)
    }
    stratus.Binary(data) -> {
      // Handle compressed binary data if decompressor is available
      case state.decompressor {
        option.Some(decompressor) -> {
          case decompress_data(data, decompressor) {
            Ok(text) -> {
              state.on_event(text)
              stratus.continue(state)
            }
            Error(_err) -> {
              // Skip frames that fail to decompress
              stratus.continue(state)
            }
          }
        }
        option.None -> {
          // No decompressor, ignore binary messages
          stratus.continue(state)
        }
      }
    }
    stratus.User(_) -> {
      // No custom user messages in this implementation
      stratus.continue(state)
    }
  }
}

/// Handle WebSocket connection close
fn handle_close(state: ConnectionState) -> Nil {
  // Reconnect from the beginning
  start_with_retry_internal(state.config, state.on_event, 0)
}

/// Calculate exponential backoff capped at 60 seconds
fn calculate_backoff(retry_count: Int) -> Int {
  case retry_count {
    0 -> 1
    1 -> 2
    2 -> 4
    3 -> 8
    4 -> 16
    5 -> 32
    _ -> 60
  }
}

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
