defmodule LatticeObserverTest.Observed.InvocationTest do
  use ExUnit.Case
  alias LatticeObserver.Observed.{Lattice, Invocation}
  alias TestSupport.CloudEvents

  @test_host "Nxxx"

  describe "Observed invocation success and fail are recorded" do
    test "Success and fail counts accumulate" do
      l = Lattice.new()

      evt =
        CloudEvents.invocation_succeeded(
          %{
            "public_key" => "Vxxx",
            "contract_id" => "wasmcloud:messaging",
            "link_name" => "default"
          },
          %{
            "public_key" => "Mxxx",
            "contract_id" => nil,
            "link_name" => " "
          },
          100,
          "messaging.DeliverMessage",
          @test_host
        )

      evt2 =
        CloudEvents.invocation_succeeded(
          %{
            "public_key" => "Vxxx",
            "contract_id" => "wasmcloud:messaging",
            "link_name" => "default"
          },
          %{
            # note the '2'
            "public_key" => "Mxxx2",
            "contract_id" => nil,
            "link_name" => " "
          },
          500,
          "messaging.DeliverMessage",
          @test_host
        )

      evt3 =
        CloudEvents.invocation_failed(
          %{
            "public_key" => "Vxxx",
            "contract_id" => "wasmcloud:messaging",
            "link_name" => "default"
          },
          %{
            # note the '2'
            "public_key" => "Mxxx2",
            "contract_id" => nil,
            "link_name" => " "
          },
          500,
          "messaging.DeliverMessage",
          @test_host
        )

      # Reverse an operation (show that bi-directional doesn't merge to 1 dir)
      evt4 =
        CloudEvents.invocation_succeeded(
          %{
            # note the '2'
            "public_key" => "Mxxx2",
            "contract_id" => nil,
            "link_name" => " "
          },
          %{
            "public_key" => "Vxxx",
            "contract_id" => "wasmcloud:messaging",
            "link_name" => "default"
          },
          500,
          "messaging.DeliverMessage",
          @test_host
        )

      l =
        [evt, evt, evt2, evt3, evt4]
        |> Enum.reduce(l, fn x, acc -> Lattice.apply_event(acc, x) end)

      assert {:ok,
              %Invocation.InvocationLog{
                fail_count: 0,
                from: %Invocation.Entity{
                  contract_id: "wasmcloud:messaging",
                  link_name: "default",
                  public_key: "Vxxx"
                },
                operation: "messaging.DeliverMessage",
                success_count: 2,
                to: %Invocation.Entity{
                  contract_id: nil,
                  link_name: nil,
                  public_key: "Mxxx"
                },
                total_bytes: 200
              }} ==
               Lattice.lookup_invocation_log(
                 l,
                 %Invocation.Entity{
                   public_key: "Vxxx",
                   contract_id: "wasmcloud:messaging",
                   link_name: "default"
                 },
                 %Invocation.Entity{
                   public_key: "Mxxx",
                   contract_id: nil,
                   link_name: nil
                 },
                 "messaging.DeliverMessage"
               )

      assert {:ok,
              %Invocation.InvocationLog{
                fail_count: 1,
                from: %Invocation.Entity{
                  contract_id: "wasmcloud:messaging",
                  link_name: "default",
                  public_key: "Vxxx"
                },
                operation: "messaging.DeliverMessage",
                success_count: 1,
                to: %Invocation.Entity{contract_id: nil, link_name: nil, public_key: "Mxxx2"},
                total_bytes: 1000
              }} ==
               Lattice.lookup_invocation_log(
                 l,
                 %Invocation.Entity{
                   public_key: "Vxxx",
                   contract_id: "wasmcloud:messaging",
                   link_name: "default"
                 },
                 %Invocation.Entity{
                   ## note the '2' here
                   public_key: "Mxxx2",
                   contract_id: nil,
                   link_name: nil
                 },
                 "messaging.DeliverMessage"
               )

      assert {:ok,
              %Invocation.InvocationLog{
                fail_count: 0,
                from: %Invocation.Entity{contract_id: nil, link_name: nil, public_key: "Mxxx2"},
                operation: "messaging.DeliverMessage",
                success_count: 1,
                to: %Invocation.Entity{
                  contract_id: "wasmcloud:messaging",
                  link_name: "default",
                  public_key: "Vxxx"
                },
                total_bytes: 500
              }} ==
               Lattice.lookup_invocation_log(
                 l,
                 %Invocation.Entity{
                   ## note the '2' here
                   public_key: "Mxxx2",
                   contract_id: nil,
                   link_name: nil
                 },
                 %Invocation.Entity{
                   public_key: "Vxxx",
                   contract_id: "wasmcloud:messaging",
                   link_name: "default"
                 },
                 "messaging.DeliverMessage"
               )
    end
  end
end
