defmodule Eclipse.Game.ScannerTest do
  use ExUnit.Case, async: true

  alias Eclipse.Game.Scanner

  describe "advance/2" do
    test "moves position forward by speed" do
      scanner = %Scanner{position: 0.0, speed: 0.5}
      {advanced, _from, _to, _wrapped?} = Scanner.advance(scanner, 24)
      assert advanced.position == 0.5
    end

    test "returns no clear range when within same column" do
      scanner = %Scanner{position: 0.0, speed: 0.5}
      {_scanner, from, to, wrapped?} = Scanner.advance(scanner, 24)
      assert from == -1
      assert to == -1
      refute wrapped?
    end

    test "returns clear range when crossing column boundary" do
      scanner = %Scanner{position: 0.5, speed: 0.5}
      {_scanner, from, to, wrapped?} = Scanner.advance(scanner, 24)
      assert from == 0
      assert to == 0
      refute wrapped?
    end

    test "wraps around at board width" do
      scanner = %Scanner{position: 23.5, speed: 1.0}
      {wrapped, from, to, wrapped?} = Scanner.advance(scanner, 24)
      assert wrapped.position == 0.5
      assert from == 23
      assert to == 23
      assert wrapped?
    end

    test "handles multi-column sweep" do
      scanner = %Scanner{position: 5.0, speed: 2.0}
      {advanced, from, to, wrapped?} = Scanner.advance(scanner, 24)
      assert advanced.position == 7.0
      assert from == 5
      assert to == 6
      refute wrapped?
    end
  end
end
