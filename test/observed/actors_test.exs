defmodule LatticeObserverTest.Observed.ActorsTest do
  use ExUnit.Case
  alias LatticeObserver.Observed.{Lattice, Instance, Actor}
  alias TestSupport.CloudEvents

  @test_spec "testapp"
  @test_host "Nxxx"

  describe "Observed Lattice Monitors Actor Events" do
    test "Adds and Removes actors" do
      start = CloudEvents.actor_started("Mxxx", "abc123", @test_spec, @test_host)
      l = Lattice.new()
      l = Lattice.apply_event(l, start)

      assert l == %Lattice{
               Lattice.new()
               | actors: %{
                   "Mxxx" => %Actor{
                     call_alias: "",
                     capabilities: ["test", "test2"],
                     id: "Mxxx",
                     instances: [
                       %Instance{
                         host_id: "Nxxx",
                         id: "abc123",
                         revision: 0,
                         annotations: %{"wasmcloud.dev/appspec" => "testapp"},
                         version: "1.0"
                       }
                     ],
                     issuer: "ATESTxxx",
                     name: "Test Actor",
                     tags: ""
                   }
                 },
                 claims: %{
                   "Mxxx" => %LatticeObserver.Observed.Claims{
                     call_alias: "",
                     caps: "test,test2",
                     iss: "ATESTxxx",
                     name: "Test Actor",
                     rev: 0,
                     sub: "Mxxx",
                     tags: "",
                     version: "1.0"
                   }
                 },
                 instance_tracking: %{}
             }

      stop = CloudEvents.actor_stopped("Mxxx", "abc123", @test_spec, @test_host)
      l = Lattice.apply_event(l, stop)
      # ensure idempotence
      l = Lattice.apply_event(l, stop)

      assert l == %Lattice{
               Lattice.new()
               | actors: %{},
                 claims: %{
                   "Mxxx" => %LatticeObserver.Observed.Claims{
                     call_alias: "",
                     caps: "test,test2",
                     iss: "ATESTxxx",
                     name: "Test Actor",
                     rev: 0,
                     sub: "Mxxx",
                     tags: "",
                     version: "1.0"
                   }
                 }
             }
    end
  end
end
