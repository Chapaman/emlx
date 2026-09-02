import Config

# Runtime bounds for the jit/compile eval-closure cache. Uncomment to cap
# `:emlx_compile_closures`. Both default to :infinity. See config/dev.exs.
# config :emlx, compile_cache_max_items: 1024
# config :emlx, compile_cache_ttl: :timer.minutes(30)

if config_env() == :test do
  config :emlx, :add_backend_on_inspect, false

  # Opt-in: recompile with both debug-assertion flags on so
  # debug_flags_functional_test.exs can exercise their actual raise behavior.
  # compile_env is baked in at compile time, so this can't be toggled at
  # runtime — see that file's moduledoc for the invocation.
  if System.get_env("EMLX_DEBUG_FLAGS") == "1" do
    config :emlx, detect_non_finites: true, enable_bounds_check: true, compiler_debug: true
  end
end
