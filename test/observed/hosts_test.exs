defmodule LatticeObserverTest.Observed.HostsTest do
  use ExUnit.Case
  alias LatticeObserver.Observed.{Lattice, EventProcessor}
  alias TestSupport.CloudEvents

  @test_host "Nxxx"
  @test_host2 "Nxxxy"

  describe "Observed Lattice Monitors Host Events" do
    test "Removing a host removes all instances on that host" do
      started =
        CloudEvents.host_started(
          @test_host,
          %{test: "yes"},
          "orange-pelican-5"
        )

      started2 =
        CloudEvents.host_started(
          @test_host2,
          %{test: "maybe"},
          "yellow-cat-6"
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
      assert (l.hosts |> Map.values() |> List.first()).friendly_name == "yellow-cat-6"
      assert Map.keys(l.instance_tracking) == ["abc123", "abc456", "abc789"]
      assert l.providers == %{}
      assert l.actors == %{}
    end

    test "Launching a previously killed host clears out lattice cache artifacts" do
      started =
        CloudEvents.host_started(
          @test_host,
          %{test: "yes"},
          "orange-button-5"
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

      l =
        Lattice.new()
        |> Lattice.apply_event(started)
        |> Lattice.apply_event(actor1)
        |> Lattice.apply_event(actor2)
        |> Lattice.apply_event(provider)

      assert Map.keys(l.hosts) == ["Nxxx"]
      assert (l.hosts |> Map.values() |> List.first()).friendly_name == "orange-button-5"
      assert Map.keys(l.instance_tracking) == ["abc123", "abc456", "abc789"]

      # Host is killed forcefully and starts again using the same seed private key
      l =
        Lattice.new()
        |> Lattice.apply_event(started)

      assert l.providers == %{}
      assert l.actors == %{}
    end

    test "Host started event produces a healthy host and stopped removes host" do
      started =
        CloudEvents.host_started(
          @test_host,
          %{test: "yes"},
          "active-racoon-1"
        )

      stamp = EventProcessor.timestamp_from_iso8601(started.time)

      l = Lattice.apply_event(Lattice.new(), started)
      assert l.hosts[@test_host].status == :healthy
      assert l.hosts[@test_host].last_seen == stamp

      stopped = CloudEvents.host_stopped(@test_host)
      l = Lattice.apply_event(l, stopped)

      assert l ==
               Lattice.new()
    end

    # updated heartbeat shape
    #  "actors": {
    #   "MB2ZQB6ROOMAYBO4ZCTFYWN7YIVBWA3MTKZYAQKJMTIHE2ELLRW2E3ZW": 10
    #   },
    #   "friendly_name": "wandering-meadow-5880",
    #   "labels": {
    #     "hostcore.arch": "aarch64",
    #     "hostcore.os": "macos",
    #     "hostcore.osfamily": "unix"
    #   },
    #   "providers": [
    #     {
    #       "link_name": "default",
    #       "public_key": "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M"
    #     }
    #   ],
    #   "uptime_human": "1 minute, 32 seconds",
    #   "uptime_seconds": 92,
    #   "version": "0.60.0"

    test "Propertly records LEGACY host heartbeat" do
      hb = CloudEvents.host_heartbeat_old(@test_host, %{foo: "bar", baz: "biz"})
      stamp = EventProcessor.timestamp_from_iso8601(hb.time)
      l = Lattice.apply_event(Lattice.new(), hb)

      assert l.hosts[@test_host].labels == %{baz: "biz", foo: "bar"}
      assert l.hosts[@test_host].status == :healthy
      assert l.hosts[@test_host].last_seen == stamp

      hb2 = CloudEvents.host_heartbeat_old(@test_host, %{foo: "bar", baz: "biz"})
      stamp2 = EventProcessor.timestamp_from_iso8601(hb2.time)
      l = Lattice.apply_event(l, hb2)

      assert l.hosts[@test_host].labels == %{baz: "biz", foo: "bar"}
      assert l.hosts[@test_host].status == :healthy
      assert l.hosts[@test_host].last_seen == stamp2

      hb3 =
        CloudEvents.host_heartbeat(
          @test_host,
          %{foo: "bar"},
          [
            %{
              "public_key" => "Mxxxx",
              "instance_id" => "iid1"
            },
            %{
              "public_key" => "Mxxxy",
              "instance_id" => "iid2"
            }
          ],
          [
            %{
              "public_key" => "Vxxxxx",
              "instance_id" => "iid3",
              "contract_id" => "wasmcloud:test",
              "link_name" => "default"
            }
          ]
        )

      # Scenario: heartbeat contains fewer actors than the previous one, yet
      # the lattice did not receive an actor stopped event.
      hb4 =
        CloudEvents.host_heartbeat(
          @test_host,
          %{foo: "bar"},
          [
            %{
              "public_key" => "Mxxxx",
              "instance_id" => "iid1"
            }
          ],
          [
            %{
              "public_key" => "Vxxxxx",
              "instance_id" => "iid3",
              "contract_id" => "wasmcloud:test",
              "link_name" => "default"
            }
          ]
        )

      l = Lattice.apply_event(Lattice.new(), hb3) |> Lattice.apply_event(hb4)

      # The Mxxxy actor isn't here because of authoritative heartbeats
      assert l.actors == %{
               "Mxxxx" => %LatticeObserver.Observed.Actor{
                 call_alias: "",
                 capabilities: [],
                 id: "Mxxxx",
                 instances: [
                   %LatticeObserver.Observed.Instance{
                     host_id: "Nxxx",
                     id: "iid1",
                     revision: 0,
                     spec_id: "",
                     version: ""
                   }
                 ],
                 issuer: "",
                 name: "unavailable",
                 tags: ""
               }
             }

      assert l.providers == %{
               {"Vxxxxx", "default"} => %LatticeObserver.Observed.Provider{
                 contract_id: "wasmcloud:test",
                 id: "Vxxxxx",
                 instances: [
                   %LatticeObserver.Observed.Instance{
                     host_id: "Nxxx",
                     id: "iid3",
                     revision: 0,
                     spec_id: "",
                     version: ""
                   }
                 ],
                 issuer: "",
                 link_name: "default",
                 name: "unavailable",
                 tags: ""
               }
             }
    end

    test "Properly records host heartbeat" do
      hb = CloudEvents.host_heartbeat(@test_host, %{foo: "bar", baz: "biz"})
      stamp = EventProcessor.timestamp_from_iso8601(hb.time)
      l = Lattice.apply_event(Lattice.new(), hb)

      assert l.hosts[@test_host].labels == %{baz: "biz", foo: "bar"}
      assert l.hosts[@test_host].status == :healthy
      assert l.hosts[@test_host].last_seen == stamp

      hb2 = CloudEvents.host_heartbeat(@test_host, %{foo: "bar", baz: "biz"})
      stamp2 = EventProcessor.timestamp_from_iso8601(hb2.time)
      l = Lattice.apply_event(l, hb2)

      assert l.hosts[@test_host].labels == %{baz: "biz", foo: "bar"}
      assert l.hosts[@test_host].status == :healthy
      assert l.hosts[@test_host].last_seen == stamp2

      hb3 =
        CloudEvents.host_heartbeat(
          @test_host,
          %{foo: "bar"},
          %{
            "Mxxxx" => 1,
            "Mxxxy" => 2
          },
          [
            %{
              "public_key" => "Vxxxxx",
              "contract_id" => "wasmcloud:test",
              "link_name" => "default"
            }
          ]
        )

      # Scenario: heartbeat contains fewer actors than the previous one, yet
      # the lattice did not receive an actor stopped event.
      hb4 =
        CloudEvents.host_heartbeat(
          @test_host,
          %{foo: "bar"},
          %{
            "Mxxxx" => 1
          },
          [
            %{
              "public_key" => "Vxxxxx",
              "contract_id" => "wasmcloud:test",
              "link_name" => "default"
            }
          ]
        )

      l = Lattice.apply_event(Lattice.new(), hb3) |> Lattice.apply_event(hb4)

      # The Mxxxy actor isn't here because of authoritative heartbeats
      assert l.actors == %{
               "Mxxxx" => %LatticeObserver.Observed.Actor{
                 call_alias: "",
                 capabilities: [],
                 id: "Mxxxx",
                 instances: [
                   %LatticeObserver.Observed.Instance{
                     host_id: "Nxxx",
                     id: "n/a",
                     revision: 0,
                     spec_id: "",
                     version: ""
                   }
                 ],
                 issuer: "",
                 name: "unavailable",
                 tags: ""
               }
             }

      assert l.providers == %{
               {"Vxxxxx", "default"} => %LatticeObserver.Observed.Provider{
                 contract_id: "n/a",
                 id: "Vxxxxx",
                 instances: [
                   %LatticeObserver.Observed.Instance{
                     host_id: "Nxxx",
                     id: "n/a",
                     revision: 0,
                     spec_id: "",
                     version: ""
                   }
                 ],
                 issuer: "",
                 link_name: "default",
                 name: "unavailable",
                 tags: ""
               }
             }
    end
  end
end
