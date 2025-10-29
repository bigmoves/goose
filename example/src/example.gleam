import gleam/io
import gleam/option
import gleam/string
import goose

pub fn main() -> Nil {
  let config =
    goose.JetstreamConfig(
      endpoint: "wss://jetstream2.us-east.bsky.network/subscribe",
      wanted_collections: [],
      wanted_dids: [],
      cursor: option.None,
      max_message_size_bytes: option.None,
      compress: True,
      require_hello: False,
    )

  io.println("Starting Jetstream consumer...")
  io.println("Connected to: " <> config.endpoint)
  io.println("Listening for all events...\n")

  // Start consuming and log all events
  goose.start_consumer(config, fn(json_event) {
    let event = goose.parse_event(json_event)

    case event {
      goose.CommitEvent(did, time_us, commit) -> {
        io.println(
          "COMMIT | "
          <> commit.operation
          <> " | "
          <> commit.collection
          <> " | "
          <> commit.rkey
          <> " | DID: "
          <> did
          <> " | Time: "
          <> string.inspect(time_us),
        )
      }
      goose.IdentityEvent(did, time_us, identity) -> {
        io.println(
          "IDENTITY | Handle: "
          <> identity.handle
          <> " | DID: "
          <> did
          <> " | Seq: "
          <> string.inspect(identity.seq)
          <> " | Time: "
          <> string.inspect(time_us),
        )
      }
      goose.AccountEvent(did, time_us, account) -> {
        let status = case account.active {
          True -> "ACTIVE"
          False -> "INACTIVE"
        }
        io.println(
          "ACCOUNT | Status: "
          <> status
          <> " | DID: "
          <> did
          <> " | Seq: "
          <> string.inspect(account.seq)
          <> " | Time: "
          <> string.inspect(time_us),
        )
      }
      goose.UnknownEvent(raw) -> {
        io.println("UNKNOWN | " <> raw)
      }
    }
  })
}
