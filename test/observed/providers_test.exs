defmodule LatticeObserverTest.Observed.ProvidersTest do
  use ExUnit.Case
  alias LatticeObserver.Observed.{Lattice, Instance, Provider, EventProcessor}
  alias TestSupport.CloudEvents

  @test_spec "testapp"
  @test_spec_2 "othertestapp"
  @test_host "Nxxx"
  @test_host2 "Nxxy"
  @test_contract "wasmcloud:test"

  describe "Observed Lattice Monitors Provider Events" do
    test "Adds and Removes Providers" do
      start =
        CloudEvents.provider_started(
          "Vxxx",
          @test_contract,
          "default",
          "n/a",
          @test_spec,
          @test_host
        )

      l = Lattice.new()
      l = Lattice.apply_event(l, start)
      stamp1 = EventProcessor.timestamp_from_iso8601(start.time)

      orig_desired = %Lattice{
        Lattice.new()
        | instance_tracking: %{
            "n/a" => stamp1
          },
          claims: %{
            "Vxxx" => %LatticeObserver.Observed.Claims{
              call_alias: "",
              caps: "",
              iss: "ATESTxxx",
              name: "test provider",
              rev: 2,
              sub: "Vxxx",
              tags: "a,b",
              version: "1.0"
            }
          },
          providers: %{
            {"Vxxx", "default"} => %Provider{
              contract_id: "wasmcloud:test",
              id: "Vxxx",
              instances: [
                %Instance{
                  host_id: "Nxxx",
                  id: "n/a",
                  revision: 2,
                  spec_id: "testapp",
                  version: "1.0"
                }
              ],
              issuer: "ATESTxxx",
              link_name: "default",
              name: "test provider",
              tags: "a,b"
            }
          }
      }

      assert l == orig_desired

      assert Lattice.providers_in_appspec(orig_desired, "testapp") ==
               [
                 %{
                   contract_id: "wasmcloud:test",
                   host_id: "Nxxx",
                   instance_id: "n/a",
                   link_name: "default",
                   provider_id: "Vxxx"
                 }
               ]

      stop =
        CloudEvents.provider_stopped(
          "Vxxx",
          @test_contract,
          "default",
          "abc123",
          @test_spec,
          @test_host
        )

      l = Lattice.apply_event(l, stop)

      # Note that the instance tracking field is now deprecated/useless
      desired = %Lattice{
        Lattice.new()
        | providers: %{},
          instance_tracking: %{"n/a" => stamp1},
          claims: %{
            "Vxxx" => %LatticeObserver.Observed.Claims{
              call_alias: "",
              caps: "",
              iss: "ATESTxxx",
              name: "test provider",
              rev: 2,
              sub: "Vxxx",
              tags: "a,b",
              version: "1.0"
            }
          }
      }

      assert l == desired
      l = Lattice.apply_event(l, stop)
      assert l == desired
      l = Lattice.apply_event(l, start)
      assert l == orig_desired
    end

    test "Stores multiple instances of a provider across hosts" do
      start =
        CloudEvents.provider_started(
          "Vxxx",
          @test_contract,
          "default",
          "n/a",
          @test_spec,
          @test_host
        )

      l = Lattice.apply_event(Lattice.new(), start)

      start2 =
        CloudEvents.provider_started(
          "Vxxx",
          @test_contract,
          "not-so-default",
          "n/a",
          @test_spec,
          @test_host
        )

      stamp2 = EventProcessor.timestamp_from_iso8601(start2.time)
      l = Lattice.apply_event(l, start2)

      assert l == %Lattice{
               Lattice.new()
               | instance_tracking: %{"n/a" => stamp2},
                 providers: %{
                   {"Vxxx", "default"} => %LatticeObserver.Observed.Provider{
                     contract_id: "wasmcloud:test",
                     id: "Vxxx",
                     instances: [
                       %LatticeObserver.Observed.Instance{
                         host_id: "Nxxx",
                         id: "n/a",
                         revision: 2,
                         spec_id: "testapp",
                         version: "1.0"
                       }
                     ],
                     issuer: "ATESTxxx",
                     link_name: "default",
                     name: "test provider",
                     tags: "a,b"
                   },
                   {"Vxxx", "not-so-default"} => %LatticeObserver.Observed.Provider{
                     contract_id: "wasmcloud:test",
                     id: "Vxxx",
                     instances: [
                       %LatticeObserver.Observed.Instance{
                         host_id: "Nxxx",
                         id: "n/a",
                         revision: 2,
                         spec_id: "testapp",
                         version: "1.0"
                       }
                     ],
                     issuer: "ATESTxxx",
                     link_name: "not-so-default",
                     name: "test provider",
                     tags: "a,b"
                   }
                 },
                 claims: %{
                   "Vxxx" => %LatticeObserver.Observed.Claims{
                     call_alias: "",
                     caps: "",
                     iss: "ATESTxxx",
                     name: "test provider",
                     rev: 2,
                     sub: "Vxxx",
                     tags: "a,b",
                     version: "1.0"
                   }
                 }
             }

      # Add a new instance from a different spec
      start3 =
        CloudEvents.provider_started(
          "Vxxx",
          @test_contract,
          "default",
          "n/a",
          @test_spec_2,
          @test_host2
        )

      stamp3 = EventProcessor.timestamp_from_iso8601(start3.time)

      l = Lattice.apply_event(l, start3)

      assert l == %Lattice{
               Lattice.new()
               | instance_tracking: %{
                   "n/a" => stamp3
                 },
                 providers: %{
                   {"Vxxx", "default"} => %Provider{
                     contract_id: "wasmcloud:test",
                     issuer: "ATESTxxx",
                     name: "test provider",
                     tags: "a,b",
                     id: "Vxxx",
                     instances: [
                       %Instance{
                         host_id: "Nxxy",
                         id: "n/a",
                         spec_id: "othertestapp",
                         revision: 2,
                         version: "1.0"
                       },
                       %Instance{
                         host_id: "Nxxx",
                         id: "n/a",
                         spec_id: "testapp",
                         revision: 2,
                         version: "1.0"
                       }
                     ],
                     link_name: "default"
                   },
                   {"Vxxx", "not-so-default"} => %LatticeObserver.Observed.Provider{
                     contract_id: "wasmcloud:test",
                     id: "Vxxx",
                     instances: [
                       %LatticeObserver.Observed.Instance{
                         host_id: "Nxxx",
                         id: "n/a",
                         revision: 2,
                         spec_id: "testapp",
                         version: "1.0"
                       }
                     ],
                     issuer: "ATESTxxx",
                     link_name: "not-so-default",
                     name: "test provider",
                     tags: "a,b"
                   }
                 },
                 claims: %{
                   "Vxxx" => %LatticeObserver.Observed.Claims{
                     call_alias: "",
                     caps: "",
                     iss: "ATESTxxx",
                     name: "test provider",
                     rev: 2,
                     sub: "Vxxx",
                     tags: "a,b",
                     version: "1.0"
                   }
                 }
             }
    end
  end
end
