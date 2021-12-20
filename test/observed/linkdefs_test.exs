defmodule LatticeObserverTest.Observed.LinkdefsTest do
  use ExUnit.Case
  alias LatticeObserver.Observed.Lattice
  alias TestSupport.CloudEvents

  describe "Observed Lattice Monitors Linkdef Events" do
    test "Subsequent Puts are Ignored" do
      put =
        CloudEvents.linkdef_put(
          "Mxxx",
          "Vxxx",
          "default",
          "wasmcloud:testing",
          %{foo: "bar"},
          "Nxxx"
        )

      l = Lattice.apply_event(Lattice.new(), put)

      put2 =
        CloudEvents.linkdef_put(
          "Mxxx",
          "Vxxx",
          "default",
          "wasmcloud:testing",
          %{foo: "altered"},
          "Nxxx"
        )

      l = Lattice.apply_event(l, put2)

      assert l == %LatticeObserver.Observed.Lattice{
               Lattice.new()
               | linkdefs: [
                   %LatticeObserver.Observed.LinkDefinition{
                     actor_id: "Mxxx",
                     contract_id: "wasmcloud:testing",
                     link_name: "default",
                     provider_id: "Vxxx",
                     values: %{foo: "bar"}
                   }
                 ]
             }
    end

    test "Put and Delete Work as Expected" do
      put =
        CloudEvents.linkdef_put(
          "Mxxx",
          "Vxxx",
          "default",
          "wasmcloud:testing",
          %{foo: "bar"},
          "Nxxx"
        )

      l = Lattice.apply_event(Lattice.new(), put)
      del = CloudEvents.linkdef_del("Mxxx", "Vxxx", "default", "wasmcloud:testing", "Nxxx")
      l = Lattice.apply_event(l, del)
      assert l == Lattice.new()
    end
  end
end
