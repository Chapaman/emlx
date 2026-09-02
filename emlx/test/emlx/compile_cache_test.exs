defmodule EMLX.CompileCacheTest do
  use ExUnit.Case, async: true

  alias EMLX.CompileCache

  setup do
    table = :ets.new(:compile_cache_test, [:set, :public])
    %{table: table}
  end

  defp unbounded, do: [max_items: :infinity, ttl: :infinity]

  test "unbounded cache keeps every insert", %{table: table} do
    CompileCache.put(table, :a, :fun_a, unbounded())
    CompileCache.put(table, :b, :fun_b, unbounded())

    assert CompileCache.fetch(table, :a, unbounded()) == {:ok, :fun_a}
    assert CompileCache.fetch(table, :b, unbounded()) == {:ok, :fun_b}
    assert :ets.info(table, :size) == 2
  end

  test "max_items evicts the oldest insert", %{table: table} do
    opts = [max_items: 2, ttl: :infinity]

    CompileCache.put(table, :a, :fun_a, opts)
    Process.sleep(2)
    CompileCache.put(table, :b, :fun_b, opts)
    Process.sleep(2)
    CompileCache.put(table, :c, :fun_c, opts)

    assert CompileCache.fetch(table, :a, opts) == :miss
    assert CompileCache.fetch(table, :b, opts) == {:ok, :fun_b}
    assert CompileCache.fetch(table, :c, opts) == {:ok, :fun_c}
    assert :ets.info(table, :size) == 2
  end

  test "expired TTL is a miss and deletes the row", %{table: table} do
    opts = [max_items: :infinity, ttl: 1]

    CompileCache.put(table, :a, :fun_a, opts)
    assert CompileCache.fetch(table, :a, opts) == {:ok, :fun_a}

    Process.sleep(5)

    assert CompileCache.fetch(table, :a, opts) == :miss
    assert :ets.lookup(table, :a) == []
  end

  test "re-put of the same key replaces and refreshes inserted_ms", %{table: table} do
    CompileCache.put(table, :a, :fun_old, unbounded())
    [{_, _, first_ms}] = :ets.lookup(table, :a)

    Process.sleep(2)
    CompileCache.put(table, :a, :fun_new, unbounded())

    assert :ets.info(table, :size) == 1
    assert CompileCache.fetch(table, :a, unbounded()) == {:ok, :fun_new}
    [{_, _, second_ms}] = :ets.lookup(table, :a)
    assert second_ms > first_ms
  end

  test "invalid max_items raises", %{table: table} do
    assert_raise ArgumentError, ~r/compile_cache_max_items/, fn ->
      CompileCache.put(table, :a, :fun_a, max_items: 0, ttl: :infinity)
    end

    assert_raise ArgumentError, ~r/compile_cache_max_items/, fn ->
      CompileCache.fetch(table, :a, max_items: -1, ttl: :infinity)
    end
  end

  test "invalid ttl raises", %{table: table} do
    assert_raise ArgumentError, ~r/compile_cache_ttl/, fn ->
      CompileCache.put(table, :a, :fun_a, max_items: :infinity, ttl: 0)
    end

    assert_raise ArgumentError, ~r/compile_cache_ttl/, fn ->
      CompileCache.fetch(table, :a, max_items: :infinity, ttl: "soon")
    end
  end
end
