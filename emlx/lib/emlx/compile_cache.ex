defmodule EMLX.CompileCache do
  @moduledoc """
  Bounded ETS cache of `native_compile/3` eval closures.

  `EMLX.__compile__/4` stores one closure per `{fun, templates, hooks, device}`
  key so repeated `Nx.Defn.jit/2` of the same call site skips retrace. The
  table is unbounded unless the host application sets:

      config :emlx, compile_cache_max_items: 1024
      config :emlx, compile_cache_ttl: :timer.minutes(30)

  Both default to `:infinity`. Overflow evicts the oldest inserts (FIFO).
  TTL is counted from insert time, not last access. Two concurrent misses
  on the same key both compile; the later `put/4` wins.

  Evicting a closure does **not** free the compiled MLX program held in
  `:emlx_native_dispatch_cache`.
  """

  @table :emlx_compile_closures

  @doc false
  def table, do: @table

  @doc false
  def init(table \\ @table) do
    case :ets.whereis(table) do
      :undefined ->
        :ets.new(table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end
  end

  @doc false
  def opts do
    [
      max_items: Application.get_env(:emlx, :compile_cache_max_items, :infinity),
      ttl: Application.get_env(:emlx, :compile_cache_ttl, :infinity)
    ]
  end

  @doc false
  def fetch(table, key, opts) do
    ttl = bound!(opts, :ttl)
    # Validate both knobs on fetch and put so a bad config fails at first use.
    _max_items = bound!(opts, :max_items)

    case :ets.lookup(table, key) do
      [{^key, fun, inserted_ms}] ->
        if expired?(inserted_ms, ttl) do
          :ets.delete(table, key)
          :miss
        else
          {:ok, fun}
        end

      [] ->
        :miss
    end
  end

  @doc false
  def put(table, key, fun, opts) do
    max_items = bound!(opts, :max_items)
    _ttl = bound!(opts, :ttl)

    :ets.insert(table, {key, fun, System.monotonic_time(:millisecond)})
    evict_overflow(table, max_items)
    fun
  end

  defp bound!(opts, key) do
    case Keyword.get(opts, key, :infinity) do
      :infinity ->
        :infinity

      n when is_integer(n) and n > 0 ->
        n

      other ->
        raise ArgumentError,
              "config :emlx, #{env_key(key)} must be :infinity or a positive integer, got: #{inspect(other)}"
    end
  end

  defp env_key(:max_items), do: :compile_cache_max_items
  defp env_key(:ttl), do: :compile_cache_ttl

  defp expired?(_inserted_ms, :infinity), do: false

  defp expired?(inserted_ms, ttl) do
    System.monotonic_time(:millisecond) - inserted_ms >= ttl
  end

  defp evict_overflow(_table, :infinity), do: :ok

  defp evict_overflow(table, max_items) do
    overflow = :ets.info(table, :size) - max_items

    if overflow > 0 do
      oldest_keys =
        :ets.foldl(fn {key, _fun, ms}, acc -> [{ms, key} | acc] end, [], table)
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.take(overflow)
        |> Enum.map(&elem(&1, 1))

      Enum.each(oldest_keys, &:ets.delete(table, &1))
    else
      :ok
    end
  end
end
