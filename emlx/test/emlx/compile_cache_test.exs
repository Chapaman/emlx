defmodule EMLX.CompileCacheTest do
  use ExUnit.Case, async: true

  alias EMLX.CompileCache

  setup do
    table = :ets.new(:compile_cache_test, [:set, :public])
    %{table: table}
  end

  defp unbounded, do: [max_items: :infinity]
  defp entry_count(table), do: :ets.select_count(table, [{{:"$1", :_, :_, :_}, [], [true]}])

  test "unbounded cache keeps every insert", %{table: table} do
    CompileCache.put(table, :a, :fun_a, unbounded())
    CompileCache.put(table, :b, :fun_b, unbounded())

    assert CompileCache.fetch(table, :a) == {:ok, :fun_a}
    assert CompileCache.fetch(table, :b) == {:ok, :fun_b}
    assert entry_count(table) == 2
  end

  test "max_items evicts the oldest insert", %{table: table} do
    opts = [max_items: 2]

    CompileCache.put(table, :a, :fun_a, opts)
    CompileCache.put(table, :b, :fun_b, opts)
    CompileCache.put(table, :c, :fun_c, opts)

    assert CompileCache.fetch(table, :a) == {:error, :cache_miss}
    assert CompileCache.fetch(table, :b) == {:ok, :fun_b}
    assert CompileCache.fetch(table, :c) == {:ok, :fun_c}
    assert entry_count(table) == 2
  end

  test "expire_entries deletes rows older than ttl", %{table: table} do
    CompileCache.put(table, :a, :fun_a, unbounded())
    assert CompileCache.fetch(table, :a) == {:ok, :fun_a}

    Process.sleep(5)
    assert CompileCache.expire_entries(table, 1) == 1

    assert CompileCache.fetch(table, :a) == {:error, :cache_miss}
    assert :ets.lookup(table, :a) == []
  end

  test "GenServer expire tick drops stale entries", %{table: table} do
    name = :"compile_cache_ttl_#{System.unique_integer([:positive])}"
    pid = start_supervised!({CompileCache, table: table, name: name, ttl: 10})

    CompileCache.put(table, :a, :fun_a, unbounded())
    Process.sleep(15)
    send(pid, :expire_entries)

    assert CompileCache.fetch(table, :a) == {:error, :cache_miss}
  end

  test "re-put of the same key replaces and refreshes inserted_ms", %{table: table} do
    CompileCache.put(table, :a, :fun_old, unbounded())
    [{_, _, first_ms, first_idx}] = :ets.lookup(table, :a)

    Process.sleep(2)
    CompileCache.put(table, :a, :fun_new, unbounded())

    assert entry_count(table) == 1
    assert CompileCache.fetch(table, :a) == {:ok, :fun_new}
    [{_, _, second_ms, second_idx}] = :ets.lookup(table, :a)
    assert second_ms > first_ms
    assert second_idx > first_idx
  end

  test "invalid max_items raises", %{table: table} do
    assert_raise ArgumentError, ~r/compile_cache_max_items/, fn ->
      CompileCache.put(table, :a, :fun_a, max_items: 0)
    end
  end

  test "invalid ttl raises", %{table: table} do
    assert_raise ArgumentError, ~r/compile_cache_ttl/, fn ->
      CompileCache.start_link(
        table: table,
        ttl: 0,
        name: :"compile_cache_bad_ttl_#{System.unique_integer([:positive])}"
      )
    end
  end
end
