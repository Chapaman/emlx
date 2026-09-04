defmodule EMLX.CompileCacheTest do
  use ExUnit.Case, async: true

  alias EMLX.CompileCache

  setup do
    name = :"compile_cache_#{System.unique_integer([:positive])}"
    start_supervised!({CompileCache, name: name, max_items: :infinity, ttl: :infinity}, id: name)
    %{name: name}
  end

  test "unbounded cache keeps every insert", %{name: name} do
    CompileCache.put(:a, :fun_a, name)
    CompileCache.put(:b, :fun_b, name)

    assert CompileCache.fetch(:a, name) == {:ok, :fun_a}
    assert CompileCache.fetch(:b, name) == {:ok, :fun_b}
  end

  test "max_items evicts the oldest insert" do
    name = :"compile_cache_max_#{System.unique_integer([:positive])}"
    start_supervised!({CompileCache, name: name, max_items: 2, ttl: :infinity}, id: name)

    CompileCache.put(:a, :fun_a, name)
    CompileCache.put(:b, :fun_b, name)
    CompileCache.put(:c, :fun_c, name)

    assert CompileCache.fetch(:a, name) == {:error, :cache_miss}
    assert CompileCache.fetch(:b, name) == {:ok, :fun_b}
    assert CompileCache.fetch(:c, name) == {:ok, :fun_c}
  end

  test "expire tick drops stale entries" do
    name = :"compile_cache_ttl_#{System.unique_integer([:positive])}"
    pid = start_supervised!({CompileCache, name: name, max_items: :infinity, ttl: 10}, id: name)

    CompileCache.put(:a, :fun_a, name)
    Process.sleep(15)
    send(pid, :expire_entries)

    assert CompileCache.fetch(:a, name) == {:error, :cache_miss}
  end

  test "re-put of the same key replaces the value", %{name: name} do
    CompileCache.put(:a, :fun_old, name)
    CompileCache.put(:a, :fun_new, name)

    assert CompileCache.fetch(:a, name) == {:ok, :fun_new}
  end

  test "invalid max_items raises" do
    assert_raise ArgumentError, ~r/EMLX.CompileCache/, fn ->
      CompileCache.start_link(
        max_items: 0,
        name: :"compile_cache_bad_max_#{System.unique_integer([:positive])}"
      )
    end
  end

  test "invalid ttl raises" do
    assert_raise ArgumentError, ~r/EMLX.CompileCache/, fn ->
      CompileCache.start_link(
        ttl: 0,
        name: :"compile_cache_bad_ttl_#{System.unique_integer([:positive])}"
      )
    end
  end
end
