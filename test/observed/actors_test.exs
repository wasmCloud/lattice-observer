defmodule LatticeObserverTest.Observed.ActorsTest do
  use ExUnit.Case
  alias LatticeObserver.Observed.{Lattice, Instance, Actor}
  alias TestSupport.CloudEvents

  @test_spec "testapp"
  @test_host "Nxxx"
  @test_host_2 "Nyyy"

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

    test "Scaled event modifies actor list" do
      start =
        CloudEvents.actor_scaled(
          "Myyy",
          @test_spec,
          @test_host_2,
          "mything.cloud.io/actor:latest",
          1
        )

      l = Lattice.new()
      l = Lattice.apply_event(l, start)

      assert l == %Lattice{
               Lattice.new()
               | actors: %{
                   "Myyy" => %Actor{
                     call_alias: "",
                     capabilities: ["test", "test2"],
                     id: "Myyy",
                     instances: [
                       %Instance{
                         host_id: "Nyyy",
                         id: "N/A",
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
                   "Myyy" => %LatticeObserver.Observed.Claims{
                     call_alias: "",
                     caps: "test,test2",
                     iss: "ATESTxxx",
                     name: "Test Actor",
                     rev: 0,
                     sub: "Myyy",
                     tags: "",
                     version: "1.0"
                   }
                 },
                 instance_tracking: %{}
             }

      scale_up =
        CloudEvents.actor_scaled(
          "Myyy",
          @test_spec,
          @test_host_2,
          "mything.cloud.io/actor:latest",
          500
        )

      l = Lattice.apply_event(l, scale_up)
      assert l.actors["Myyy"].instances |> length() == 500

      scale_down =
        CloudEvents.actor_scaled(
          "Myyy",
          @test_spec,
          @test_host_2,
          "mything.cloud.io/actor:latest",
          123
        )

      l = Lattice.apply_event(l, scale_down)
      assert l.actors["Myyy"].instances |> length() == 123

      scale_to_zero =
        CloudEvents.actor_scaled(
          "Myyy",
          @test_spec,
          @test_host_2,
          "mything.cloud.io/actor:latest",
          0
        )

      l = Lattice.apply_event(l, scale_to_zero)
      actor = Map.get(l.actors, "Myyy", nil)
      assert is_nil(actor)
    end
  end
end
