defmodule LatticeObserverTest.Observed.DecayTest do
  use ExUnit.Case
  alias LatticeObserver.Observed.Lattice
  alias TestSupport.CloudEvents

  @test_host "Nxxx"

  describe "Observed Lattice Decays Entity Status According to Rules" do
    test "Hosts maintain different first and last seen times" do
      start_time = DateTime.utc_now()

      started =
        CloudEvents.host_started(
          @test_host,
          %{test: "yes"}
        )

      started = %{started | time: start_time |> DateTime.to_iso8601()}
      l = Lattice.new() |> Lattice.apply_event(started)

      hb = CloudEvents.host_heartbeat(@test_host, %{foo: "bar", baz: "biz"})
      hb = %{hb | time: DateTime.add(start_time, 20, :second) |> DateTime.to_iso8601()}
      l = l |> Lattice.apply_event(hb)

      assert l.hosts[@test_host].first_seen == start_time
      assert l.hosts[@test_host].first_seen != l.hosts[@test_host].last_seen
    end

    test "Host status decays according to rules" do
      start_time = DateTime.utc_now()

      started =
        CloudEvents.host_started(
          @test_host,
          %{test: "yes"}
        )

      started = %{started | time: start_time |> DateTime.to_iso8601()}

      l = Lattice.new() |> Lattice.apply_event(started)
      tick = CloudEvents.decay_tick(DateTime.add(start_time, 20, :second))
      l = l |> Lattice.apply_event(tick)
      assert l.hosts[@test_host].status == :healthy

      # multiple decay ticks within the same time period do not double
      # up and cause decay - e.g. decay tick processing is
      # idempotent
      tick = CloudEvents.decay_tick(DateTime.add(start_time, 20, :second))
      l = l |> Lattice.apply_event(tick)
      assert l.hosts[@test_host].status == :healthy

      tick = CloudEvents.decay_tick(DateTime.add(start_time, 40, :second))
      l = l |> Lattice.apply_event(tick)
      assert l.hosts[@test_host].status == :warn

      tick = CloudEvents.decay_tick(DateTime.add(start_time, 80, :second))
      l = l |> Lattice.apply_event(tick)
      assert l.hosts[@test_host].status == :fail

      tick = CloudEvents.decay_tick(DateTime.add(start_time, 120, :second))
      l = l |> Lattice.apply_event(tick)
      assert l.hosts[@test_host].status == :unavailable

      tick = CloudEvents.decay_tick(DateTime.add(start_time, 160, :second))
      l = l |> Lattice.apply_event(tick)
      assert l.hosts == %{}
    end

    test "Hosts that fully decay are removed along with their resources" do
      start_time = DateTime.utc_now()

      started =
        CloudEvents.host_started(
          @test_host,
          %{test: "yes"}
        )

      started = %{started | time: start_time |> DateTime.to_iso8601()}

      actor1 = CloudEvents.actor_started("Mxxx", "abc123", "none", @test_host)

      l =
        Lattice.new()
        |> Lattice.apply_event(started)
        |> Lattice.apply_event(actor1)

      tick = CloudEvents.decay_tick(DateTime.add(start_time, 20, :second))
      l = l |> Lattice.apply_event(tick)
      assert l.hosts[@test_host].status == :healthy

      assert l.actors == %{
               "Mxxx" => %LatticeObserver.Observed.Actor{
                 call_alias: "",
                 capabilities: ["test", "test2"],
                 id: "Mxxx",
                 instances: [
                   %LatticeObserver.Observed.Instance{
                     host_id: "Nxxx",
                     id: "abc123",
                     revision: 0,
                     spec_id: "none",
                     version: "1.0"
                   }
                 ],
                 issuer: "ATESTxxx",
                 name: "Test Actor",
                 tags: ""
               }
             }

      # multiple decay ticks within the same time period do not double
      # up and cause decay - e.g. decay tick processing is
      # idempotent
      tick = CloudEvents.decay_tick(DateTime.add(start_time, 20, :second))
      l = l |> Lattice.apply_event(tick)
      assert l.hosts[@test_host].status == :healthy

      tick = CloudEvents.decay_tick(DateTime.add(start_time, 40, :second))
      l = l |> Lattice.apply_event(tick)
      assert l.hosts[@test_host].status == :warn

      tick = CloudEvents.decay_tick(DateTime.add(start_time, 80, :second))
      l = l |> Lattice.apply_event(tick)
      assert l.hosts[@test_host].status == :fail

      tick = CloudEvents.decay_tick(DateTime.add(start_time, 120, :second))
      l = l |> Lattice.apply_event(tick)
      assert l.hosts[@test_host].status == :unavailable

      assert l.actors == %{
               "Mxxx" => %LatticeObserver.Observed.Actor{
                 call_alias: "",
                 capabilities: ["test", "test2"],
                 id: "Mxxx",
                 instances: [
                   %LatticeObserver.Observed.Instance{
                     host_id: "Nxxx",
                     id: "abc123",
                     revision: 0,
                     spec_id: "none",
                     version: "1.0"
                   }
                 ],
                 issuer: "ATESTxxx",
                 name: "Test Actor",
                 tags: ""
               }
             }

      tick = CloudEvents.decay_tick(DateTime.add(start_time, 160, :second))
      l = l |> Lattice.apply_event(tick)
      assert l.hosts == %{}
      assert l.actors == %{}
    end
  end
end
