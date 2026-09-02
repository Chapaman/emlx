import Config

# Compile-time debug flags for EMLX. Both default to false (zero runtime cost).
# Enable these only during development or CI runs where you want extra assertions.
#
# After changing either flag you MUST force-recompile the affected modules:
#   mix compile --force
#
# WARNING: Both flags break MLX lazy-graph fusion by forcing eager mx::eval syncs.
# On non-unified-memory targets (Linux GPU), :enable_bounds_check incurs an extra
# GPU→CPU copy per indexed op. Never enable in production.

# Raises ArgumentError on out-of-bounds indices in gather, take, take_along_axis,
# indexed_add, and indexed_put before the NIF call.
# config :emlx, enable_bounds_check: true

# Raises ArgumentError if dot (matmul / einsum), conv, or EMLX.Fast's
# rms_norm/layer_norm/scaled_dot_product_attention kernels produce NaN or Inf.
# config :emlx, detect_non_finites: true

# Raises ArgumentError on internal lowering/to_native invariant violations in
# EMLX.Native.Expr (ref id collisions, forward/self-referencing instructions,
# double-bound result refs) that would otherwise silently miscompile instead
# of failing loudly. Unlike the two flags above, this one is cheap (no extra
# eval syncs) — it's off by default only because these bugs should never
# happen in a working compiler and the checks add wasted work on the hot
# compile-cache-miss path.
# config :emlx, compiler_debug: true

# Runtime bounds for `:emlx_compile_closures` (the jit/compile eval-closure
# cache). Both default to :infinity. TTL is milliseconds from insert time;
# overflow evicts oldest inserts. Evicting a closure does not free the
# compiled program in `:emlx_native_dispatch_cache`.
# config :emlx, compile_cache_max_items: 1024
# config :emlx, compile_cache_ttl: :timer.minutes(30)
