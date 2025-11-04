import gleam/erlang/atom

/// Opaque type for decompression context
pub type DecompressionContext

/// Opaque type for decompression dictionary
pub type DecompressionDict

/// Create a decompression context with a given buffer size
@external(erlang, "ezstd", "create_decompression_context")
pub fn create_decompression_context(buffer_size: Int) -> DecompressionContext

/// Create a decompression dictionary from binary data
@external(erlang, "ezstd", "create_ddict")
pub fn create_ddict(dict_data: BitArray) -> DecompressionDict

/// Select a dictionary for the decompression context
/// Note: ezstd returns 'ok' atom, not {ok, undefined}
@external(erlang, "ezstd", "select_ddict")
fn select_ddict_ffi(
  dctx: DecompressionContext,
  ddict: DecompressionDict,
) -> atom.Atom

/// Select a dictionary for the decompression context (safe wrapper)
pub fn select_ddict(
  dctx: DecompressionContext,
  ddict: DecompressionDict,
) -> Result(Nil, String) {
  let result_atom = select_ddict_ffi(dctx, ddict)
  case atom.to_string(result_atom) {
    "ok" -> Ok(Nil)
    err -> Error("Failed to select dictionary: " <> err)
  }
}

/// Decompress data using a dictionary
/// Note: ezstd can return either BitArray or {error, Binary}
@external(erlang, "goose_ffi", "decompress_using_ddict_safe")
pub fn decompress_using_ddict(
  data: BitArray,
  ddict: DecompressionDict,
) -> Result(BitArray, String)

/// Decompress data using a streaming context (for frames without content size)
/// Note: ezstd can return either BitArray or {error, Binary}
@external(erlang, "goose_ffi", "decompress_streaming_safe")
pub fn decompress_streaming(
  dctx: DecompressionContext,
  data: BitArray,
) -> Result(BitArray, String)
