defmodule Constrain.BinarySegmentTest do
  use ExUnit.Case, async: true

  alias Constrain.BinarySegment

  describe "parse/1" do
    test "bare variable defaults to 8-bit unsigned big integer" do
      ast = quote(do: <<x>>)
      {:<<>>, _, [segment]} = ast
      assert BinarySegment.parse(segment) == {:x, :integer, 8, 1, :unsigned, :big}
    end

    test "literal integer has nil binding" do
      ast = quote(do: <<42>>)
      {:<<>>, _, [segment]} = ast
      assert BinarySegment.parse(segment) == {nil, :integer, 8, 1, :unsigned, :big}
    end

    test "explicit size via :: shorthand" do
      ast = quote(do: <<x::16>>)
      {:<<>>, _, [segment]} = ast
      assert BinarySegment.parse(segment) == {:x, :integer, 16, 1, :unsigned, :big}
    end

    test "signed integer with explicit size" do
      ast = quote(do: <<x::signed-integer-size(8)>>)
      {:<<>>, _, [segment]} = ast
      assert BinarySegment.parse(segment) == {:x, :integer, 8, 1, :signed, :big}
    end

    test "binary type with default size" do
      ast = quote(do: <<rest::binary>>)
      {:<<>>, _, [segment]} = ast
      assert BinarySegment.parse(segment) == {:rest, :binary, :default, 8, :unsigned, :big}
    end

    test "binary type with explicit size" do
      ast = quote(do: <<a::binary-size(4)>>)
      {:<<>>, _, [segment]} = ast
      assert BinarySegment.parse(segment) == {:a, :binary, 4, 8, :unsigned, :big}
    end

    test "utf8 segment" do
      ast = quote(do: <<c::utf8>>)
      {:<<>>, _, [segment]} = ast
      assert BinarySegment.parse(segment) == {:c, :utf8, :default, 1, :unsigned, :big}
    end

    test "underscore has nil binding" do
      ast = quote(do: <<_::8>>)
      {:<<>>, _, [segment]} = ast
      assert BinarySegment.parse(segment) == {nil, :integer, 8, 1, :unsigned, :big}
    end

    test "little endian unsigned 32-bit integer" do
      ast = quote(do: <<x::little-unsigned-integer-size(32)>>)
      {:<<>>, _, [segment]} = ast
      assert BinarySegment.parse(segment) == {:x, :integer, 32, 1, :unsigned, :little}
    end

    test "float defaults to 64 bits" do
      ast = quote(do: <<f::float>>)
      {:<<>>, _, [segment]} = ast
      assert BinarySegment.parse(segment) == {:f, :float, 64, 1, :unsigned, :big}
    end

    test "bitstring type" do
      ast = quote(do: <<rest::bitstring>>)
      {:<<>>, _, [segment]} = ast
      assert BinarySegment.parse(segment) == {:rest, :bitstring, :default, 1, :unsigned, :big}
    end

    test "dynamic size via variable" do
      ast = quote(do: <<data::binary-size(n)>>)
      {:<<>>, _, [segment]} = ast
      assert BinarySegment.parse(segment) == {:data, :binary, {:dynamic, :n}, 8, :unsigned, :big}
    end

    test "bare underscore variable" do
      ast = quote(do: <<_>>)
      {:<<>>, _, [segment]} = ast
      assert BinarySegment.parse(segment) == {nil, :integer, 8, 1, :unsigned, :big}
    end
  end
end
