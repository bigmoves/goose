import gleam/option
import gleeunit
import goose

pub fn main() -> Nil {
  gleeunit.main()
}

// Test build_url with default config (no filters)
pub fn build_url_default_test() {
  let config = goose.default_config()
  let url = goose.build_url(config)

  assert url
    == "wss://jetstream2.us-east.bsky.network/subscribe?compress=false&requireHello=false"
}

// Test build_url with wanted collections
pub fn build_url_with_collections_test() {
  let config =
    goose.JetstreamConfig(
      endpoint: "wss://jetstream2.us-east.bsky.network/subscribe",
      wanted_collections: ["app.bsky.feed.post", "app.bsky.feed.like"],
      wanted_dids: [],
      cursor: option.None,
      max_message_size_bytes: option.None,
      compress: False,
      require_hello: False,
      max_backoff_seconds: 60,
      log_connection_events: True,
      log_retry_attempts: True,
    )
  let url = goose.build_url(config)

  assert url
    == "wss://jetstream2.us-east.bsky.network/subscribe?wantedCollections=app.bsky.feed.like&wantedCollections=app.bsky.feed.post&compress=false&requireHello=false"
}

// Test build_url with wanted DIDs
pub fn build_url_with_dids_test() {
  let config =
    goose.JetstreamConfig(
      endpoint: "wss://jetstream2.us-east.bsky.network/subscribe",
      wanted_collections: [],
      wanted_dids: ["did:plc:example123", "did:plc:example456"],
      cursor: option.None,
      max_message_size_bytes: option.None,
      compress: False,
      require_hello: False,
      max_backoff_seconds: 60,
      log_connection_events: True,
      log_retry_attempts: True,
    )
  let url = goose.build_url(config)

  assert url
    == "wss://jetstream2.us-east.bsky.network/subscribe?wantedDids=did:plc:example456&wantedDids=did:plc:example123&compress=false&requireHello=false"
}

// Test build_url with both collections and DIDs
pub fn build_url_with_both_test() {
  let config =
    goose.JetstreamConfig(
      endpoint: "wss://jetstream2.us-east.bsky.network/subscribe",
      wanted_collections: ["app.bsky.feed.post"],
      wanted_dids: ["did:plc:example123"],
      cursor: option.None,
      max_message_size_bytes: option.None,
      compress: False,
      require_hello: False,
      max_backoff_seconds: 60,
      log_connection_events: True,
      log_retry_attempts: True,
    )
  let url = goose.build_url(config)

  assert url
    == "wss://jetstream2.us-east.bsky.network/subscribe?wantedCollections=app.bsky.feed.post&wantedDids=did:plc:example123&compress=false&requireHello=false"
}

// Test build_url with cursor
pub fn build_url_with_cursor_test() {
  let config =
    goose.JetstreamConfig(
      endpoint: "wss://jetstream2.us-east.bsky.network/subscribe",
      wanted_collections: [],
      wanted_dids: [],
      cursor: option.Some(1_234_567_890_123_456),
      max_message_size_bytes: option.None,
      compress: False,
      require_hello: False,
      max_backoff_seconds: 60,
      log_connection_events: True,
      log_retry_attempts: True,
    )
  let url = goose.build_url(config)

  assert url
    == "wss://jetstream2.us-east.bsky.network/subscribe?cursor=1234567890123456&compress=false&requireHello=false"
}

// Test build_url with max_message_size_bytes
pub fn build_url_with_max_size_test() {
  let config =
    goose.JetstreamConfig(
      endpoint: "wss://jetstream2.us-east.bsky.network/subscribe",
      wanted_collections: [],
      wanted_dids: [],
      cursor: option.None,
      max_message_size_bytes: option.Some(1_048_576),
      compress: False,
      require_hello: False,
      max_backoff_seconds: 60,
      log_connection_events: True,
      log_retry_attempts: True,
    )
  let url = goose.build_url(config)

  assert url
    == "wss://jetstream2.us-east.bsky.network/subscribe?maxMessageSizeBytes=1048576&compress=false&requireHello=false"
}

// Test build_url with compress enabled
pub fn build_url_with_compress_test() {
  let config =
    goose.JetstreamConfig(
      endpoint: "wss://jetstream2.us-east.bsky.network/subscribe",
      wanted_collections: [],
      wanted_dids: [],
      cursor: option.None,
      max_message_size_bytes: option.None,
      compress: True,
      require_hello: False,
      max_backoff_seconds: 60,
      log_connection_events: True,
      log_retry_attempts: True,
    )
  let url = goose.build_url(config)

  assert url
    == "wss://jetstream2.us-east.bsky.network/subscribe?compress=true&requireHello=false"
}

// Test build_url with require_hello enabled
pub fn build_url_with_require_hello_test() {
  let config =
    goose.JetstreamConfig(
      endpoint: "wss://jetstream2.us-east.bsky.network/subscribe",
      wanted_collections: [],
      wanted_dids: [],
      cursor: option.None,
      max_message_size_bytes: option.None,
      compress: False,
      require_hello: True,
      max_backoff_seconds: 60,
      log_connection_events: True,
      log_retry_attempts: True,
    )
  let url = goose.build_url(config)

  assert url
    == "wss://jetstream2.us-east.bsky.network/subscribe?compress=false&requireHello=true"
}

// Test build_url with all options combined
pub fn build_url_with_all_options_test() {
  let config =
    goose.JetstreamConfig(
      endpoint: "wss://jetstream2.us-east.bsky.network/subscribe",
      wanted_collections: ["app.bsky.feed.post"],
      wanted_dids: ["did:plc:example123"],
      cursor: option.Some(9_876_543_210),
      max_message_size_bytes: option.Some(2_097_152),
      compress: True,
      require_hello: True,
      max_backoff_seconds: 60,
      log_connection_events: True,
      log_retry_attempts: True,
    )
  let url = goose.build_url(config)

  assert url
    == "wss://jetstream2.us-east.bsky.network/subscribe?wantedCollections=app.bsky.feed.post&wantedDids=did:plc:example123&cursor=9876543210&maxMessageSizeBytes=2097152&compress=true&requireHello=true"
}

// Test parsing a commit event (create operation with record)
pub fn parse_commit_event_create_test() {
  let json =
    "{\"did\":\"did:plc:test123\",\"time_us\":1234567890,\"commit\":{\"rev\":\"abc123\",\"operation\":\"create\",\"collection\":\"app.bsky.feed.post\",\"rkey\":\"post123\",\"record\":{\"text\":\"Hello world\"},\"cid\":\"cid123\"}}"

  let event = goose.parse_event(json)

  case event {
    goose.CommitEvent(did, time_us, commit) -> {
      assert did == "did:plc:test123"
      assert time_us == 1_234_567_890
      assert commit.rev == "abc123"
      assert commit.operation == "create"
      assert commit.collection == "app.bsky.feed.post"
      assert commit.rkey == "post123"
    }
    _ -> panic as "Expected CommitEvent"
  }
}

// Test parsing a commit event (delete operation without record)
pub fn parse_commit_event_delete_test() {
  let json =
    "{\"did\":\"did:plc:test456\",\"time_us\":9876543210,\"commit\":{\"rev\":\"xyz789\",\"operation\":\"delete\",\"collection\":\"app.bsky.feed.like\",\"rkey\":\"like456\"}}"

  let event = goose.parse_event(json)

  case event {
    goose.CommitEvent(did, time_us, commit) -> {
      assert did == "did:plc:test456"
      assert time_us == 9_876_543_210
      assert commit.rev == "xyz789"
      assert commit.operation == "delete"
      assert commit.collection == "app.bsky.feed.like"
      assert commit.rkey == "like456"
    }
    _ -> panic as "Expected CommitEvent"
  }
}

// Test parsing an identity event
pub fn parse_identity_event_test() {
  let json =
    "{\"did\":\"did:plc:identity123\",\"time_us\":1111111111,\"identity\":{\"did\":\"did:plc:identity123\",\"handle\":\"alice.bsky.social\",\"seq\":42,\"time\":\"2024-01-01T00:00:00Z\"}}"

  let event = goose.parse_event(json)

  case event {
    goose.IdentityEvent(did, time_us, identity) -> {
      assert did == "did:plc:identity123"
      assert time_us == 1_111_111_111
      assert identity.did == "did:plc:identity123"
      assert identity.handle == "alice.bsky.social"
      assert identity.seq == 42
      assert identity.time == "2024-01-01T00:00:00Z"
    }
    _ -> panic as "Expected IdentityEvent"
  }
}

// Test parsing an account event
pub fn parse_account_event_test() {
  let json =
    "{\"did\":\"did:plc:account789\",\"time_us\":2222222222,\"account\":{\"active\":true,\"did\":\"did:plc:account789\",\"seq\":99,\"time\":\"2024-01-02T00:00:00Z\"}}"

  let event = goose.parse_event(json)

  case event {
    goose.AccountEvent(did, time_us, account) -> {
      assert did == "did:plc:account789"
      assert time_us == 2_222_222_222
      assert account.active == True
      assert account.did == "did:plc:account789"
      assert account.seq == 99
      assert account.time == "2024-01-02T00:00:00Z"
    }
    _ -> panic as "Expected AccountEvent"
  }
}

// Test parsing unknown/invalid JSON
pub fn parse_unknown_event_test() {
  let json = "{\"unknown\":\"event\",\"type\":\"something\"}"

  let event = goose.parse_event(json)

  case event {
    goose.UnknownEvent(raw) -> {
      assert raw == json
    }
    _ -> panic as "Expected UnknownEvent"
  }
}
