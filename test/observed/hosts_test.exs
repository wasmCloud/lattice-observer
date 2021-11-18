defmodule LatticeObserverTest.Observed.HostsTest do
  use ExUnit.Case
  alias LatticeObserver.Observed.Lattice
  alias TestSupport.CloudEvents

  @test_host "Nxxx"
  @test_host2 "Nxxxy"

  describe "Observed Lattice Monitors Host Events" do
    test "Removing a host removes all instances on that host" do
      started =
        CloudEvents.host_started(
          @test_host,
          %{test: "yes"}
        )

      started2 =
        CloudEvents.host_started(
          @test_host2,
          %{test: "maybe"}
        )

      actor1 = CloudEvents.actor_started("Mxxx", "abc123", "none", @test_host)
      actor2 = CloudEvents.actor_started("Mxxx", "abc456", "none", @test_host)

      provider =
        CloudEvents.provider_started(
          "Vxxx",
          "wasmcloud:test",
          "default",
          "abc789",
          "none",
          @test_host
        )

      host1_stop = CloudEvents.host_stopped(@test_host)

      l =
        Lattice.new()
        |> Lattice.apply_event(started)
        |> Lattice.apply_event(started2)
        |> Lattice.apply_event(actor1)
        |> Lattice.apply_event(actor2)
        |> Lattice.apply_event(provider)
        |> Lattice.apply_event(host1_stop)

      assert Map.keys(l.hosts) == ["Nxxxy"]
      assert Map.keys(l.instance_tracking) == ["abc123", "abc456", "abc789"]
      assert l.providers == %{}
      assert l.actors == %{}
    end

    test "Host started event produces a healthy host and stopped removes host" do
      started =
        CloudEvents.host_started(
          @test_host,
          %{test: "yes"}
        )

      stamp = Lattice.timestamp_from_iso8601(started.time)

      l = Lattice.apply_event(Lattice.new(), started)
      assert l.hosts[@test_host].status == :healthy
      assert l.hosts[@test_host].last_seen == stamp

      stopped = CloudEvents.host_stopped(@test_host)
      l = Lattice.apply_event(l, stopped)

      assert l ==
               Lattice.new()
    end

    test "Properly records host heartbeat" do
      hb = CloudEvents.host_heartbeat(@test_host, %{foo: "bar", baz: "biz"})
      stamp = Lattice.timestamp_from_iso8601(hb.time)
      l = Lattice.apply_event(Lattice.new(), hb)

      assert l.hosts[@test_host].labels == %{baz: "biz", foo: "bar"}
      assert l.hosts[@test_host].status == :healthy
      assert l.hosts[@test_host].last_seen == stamp

      hb2 = CloudEvents.host_heartbeat(@test_host, %{foo: "bar", baz: "biz"})
      stamp2 = Lattice.timestamp_from_iso8601(hb2.time)
      l = Lattice.apply_event(l, hb2)

      assert l.hosts[@test_host].labels == %{baz: "biz", foo: "bar"}
      assert l.hosts[@test_host].status == :healthy
      assert l.hosts[@test_host].last_seen == stamp2
    end
  end
end
