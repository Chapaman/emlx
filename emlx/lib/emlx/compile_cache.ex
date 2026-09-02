defmodule EMLX.CompileCache do
  @moduledoc """
  Bounded ETS cache of `native_compile/3` eval closures.

  `EMLX.__compile__/4` stores one closure per `{fun, templates, hooks, device}`
  so repeated `Nx.Defn.jit/2` of the same call site skips retrace. Unbounded
  unless the host sets:

      config :emlx, compile_cache_max_items: 1024
      config :emlx, compile_cache_ttl: :timer.minutes(30)

  Both default to `:infinity`. Overflow is FIFO by insert index. TTL is from
  insert time and is swept by this process (`send_after(self(), :expire_entries,
  div(ttl, 2))`), not on cache reads. A sweeper that is already running re-reads
  app env each tick; if TTL is `:infinity` at start, nothing is scheduled until
  the process restarts.

  The structural program table `:emlx_native_dispatch_cache` is shared across
  call sites and is not bounded by these knobs.
  """

  use GenServer

  @table :emlx_compile_closures
  @counter :__counter__

  @doc false
  def table, do: @table

  @doc false
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    _ = current_ttl(%{ttl: Keyword.get(opts, :ttl)})
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc false
  def ensure_table(table \\ @table) when is_atom(table) do
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

    table
  end

  @doc false
  def opts do
    [
      max_items: Application.get_env(:emlx, :compile_cache_max_items, :infinity),
      ttl: Application.get_env(:emlx, :compile_cache_ttl, :infinity)
    ]
  end

  @doc false
  def fetch(table \\ @table, key) do
    case :ets.lookup(table, key) do
      [{^key, fun, _inserted_ms, _index}] -> {:ok, fun}
      _ -> {:error, :cache_miss}
    end
  end

  @doc false
  def put(table \\ @table, key, fun, opts) do
    max_items = bound!(opts, :max_items)
    index = :ets.update_counter(table, @counter, 1, {@counter, 0})
    :ets.insert(table, {key, fun, System.monotonic_time(:millisecond), index})
    evict_overflow(table, max_items, index)
    fun
  end

  @doc false
  def expire_entries(_table, :infinity), do: 0

  def expire_entries(table, ttl) when is_integer(ttl) and ttl > 0 do
    cutoff = System.monotonic_time(:millisecond) - ttl

    :ets.select_delete(table, [
      {{:"$1", :_, :"$2", :_}, [{:"=<", :"$2", cutoff}], [true]}
    ])
  end

  @impl true
  def init(opts) do
    table = Keyword.get(opts, :table) || ensure_table(@table)
    ttl = Keyword.get(opts, :ttl)
    {:ok, schedule_expire(%{table: table, ttl: ttl})}
  end

  @impl true
  def handle_info(:expire_entries, state) do
    case current_ttl(state) do
      :infinity ->
        {:noreply, state}

      ttl ->
        expire_entries(state.table, ttl)
        {:noreply, schedule_expire(state)}
    end
  end

  defp current_ttl(%{ttl: ttl}) when ttl != nil, do: bound_ttl!(ttl)
  defp current_ttl(_state), do: bound!(opts(), :ttl)

  defp schedule_expire(state) do
    case current_ttl(state) do
      :infinity ->
        state

      ttl ->
        Process.send_after(self(), :expire_entries, max(div(ttl, 2), 1))
        state
    end
  end

  defp evict_overflow(_table, :infinity, _index), do: :ok

  defp evict_overflow(table, max_items, index) do
    cutoff = index - max_items

    if cutoff > 0 do
      :ets.select_delete(table, [
        {{:"$1", :_, :_, :"$2"}, [{:"=<", :"$2", cutoff}], [true]}
      ])
    else
      :ok
    end
  end

  defp bound_ttl!(ttl), do: bound!([ttl: ttl], :ttl)

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
end
