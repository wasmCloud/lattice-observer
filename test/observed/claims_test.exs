defmodule LatticeObserverTest.Observed.ClaimsTest do
  use ExUnit.Case
  alias LatticeObserver.Observed.{Lattice, Claims}
  alias TestSupport.CloudEvents

  describe "Claims cache works appropriately" do
    test "Applying provider claims with a JSON schema stores the schema" do
      l = Lattice.new()

      l =
        Lattice.apply_claims(l, %Claims{
          sub: "Vxxxx",
          iss: "Axxxx",
          caps: "wasmcloud:othertest",
          rev: "0",
          version: "0.1",
          name: "Super ultra mega test",
          config_schema: "..this is a JSON schema.."
        })

      assert l.claims == %{
               "Vxxxx" => %LatticeObserver.Observed.Claims{
                 sub: "Vxxxx",
                 call_alias: nil,
                 iss: "Axxxx",
                 name: "Super ultra mega test",
                 caps: "wasmcloud:othertest",
                 rev: "0",
                 tags: nil,
                 version: "0.1",
                 config_schema: "..this is a JSON schema.."
               }
             }
    end

    test "Heartbeats cannot wipe out JSON schema on provider claims" do
      l = Lattice.new()

      l =
        Lattice.apply_claims(l, %Claims{
          sub: "Vxxxx",
          iss: "Axxxx",
          caps: "wasmcloud:othertest",
          rev: "0",
          version: "0.1",
          name: "Super ultra mega test",
          config_schema: "..this is a JSON schema.."
        })

      hb =
        CloudEvents.host_heartbeat(
          "Nxxxx",
          %{foo: "bar", baz: "biz"},
          %{"Mxxxx" => 1},
          [
            %{
              "link_name" => "default",
              "public_key" => "Vxxxx"
            }
          ]
        )

      l = Lattice.apply_event(l, hb)

      assert l.claims == %{
               "Vxxxx" => %LatticeObserver.Observed.Claims{
                 sub: "Vxxxx",
                 call_alias: nil,
                 iss: "Axxxx",
                 name: "Super ultra mega test",
                 caps: "wasmcloud:othertest",
                 rev: "0",
                 tags: nil,
                 version: "0.1",
                 config_schema: "..this is a JSON schema.."
               }
             }

      # applying claims w/out a schema will wipe out the previously existing one (claims are "bulk update")

      l =
        Lattice.apply_claims(l, %Claims{
          sub: "Vxxxx",
          iss: "Axxxx",
          caps: "wasmcloud:othertest",
          rev: "0",
          version: "0.1",
          name: "Super ultra mega test"
        })

      assert l.claims == %{
               "Vxxxx" => %LatticeObserver.Observed.Claims{
                 sub: "Vxxxx",
                 call_alias: nil,
                 iss: "Axxxx",
                 name: "Super ultra mega test",
                 caps: "wasmcloud:othertest",
                 rev: "0",
                 tags: nil,
                 version: "0.1",
                 config_schema: nil
               }
             }
    end

    test "Applying claims updates the cache" do
      l = Lattice.new()

      l =
        Lattice.apply_claims(l, %Claims{
          sub: "Mxxxx",
          iss: "Axxxx",
          call_alias: "test/bob",
          caps: "wasmcloud:test,wasmcloud:othertest",
          rev: "0",
          tags: "test,othertest",
          version: "0.1",
          name: "Super ultra mega test"
        })

      assert l.claims == %{
               "Mxxxx" => %Claims{
                 sub: "Mxxxx",
                 iss: "Axxxx",
                 call_alias: "test/bob",
                 caps: "wasmcloud:test,wasmcloud:othertest",
                 rev: "0",
                 tags: "test,othertest",
                 version: "0.1",
                 name: "Super ultra mega test"
               }
             }
    end

    # In this scenario, we have discovered actors/providers through partial data - e.g. we didn't see
    # the actor started event, but we saw the public key come through on a heartbeat. When we apply
    # claims after the fact, we should update the metadata to include friendly names, call aliases, etc.
    test "Applying claims with heartbeat-only-discovered actors and providers updates metadata" do
      hb =
        CloudEvents.host_heartbeat(
          "Nxxxx",
          %{foo: "bar", baz: "biz"},
          %{"Mxxxx" => 1},
          [
            %{
              "link_name" => "default",
              "public_key" => "Vxxxx"
            }
          ]
        )

      l = Lattice.new() |> Lattice.apply_event(hb)

      aclaims = %Claims{
        sub: "Mxxxx",
        name: "Super ultra mega actor",
        iss: "Axxxx",
        call_alias: "test/bob",
        caps: "wasmcloud:test,wasmcloud:othertest",
        rev: "0",
        tags: "test,othertest",
        version: "0.1"
      }

      vclaims = %Claims{
        name: "Super ultra mega provider",
        sub: "Vxxxx",
        iss: "Axxxx",
        rev: "0",
        tags: "test,othertest",
        version: "0.1"
      }

      l = l |> Lattice.apply_claims(aclaims) |> Lattice.apply_claims(vclaims)

      assert l.actors |> Map.get("Mxxxx")
    end

    test "Receiving heartbeats after applying claims augments data" do
      l = Lattice.new()

      aclaims = %Claims{
        sub: "Mxxxx",
        name: "Super ultra mega actor",
        iss: "Axxxx",
        call_alias: "test/bob",
        caps: "wasmcloud:test,wasmcloud:othertest",
        rev: "0",
        tags: "test,othertest",
        version: "0.1"
      }

      vclaims = %Claims{
        name: "Super ultra mega provider",
        sub: "Vxxxx",
        iss: "Axxxx",
        rev: "0",
        tags: "test,othertest",
        version: "0.1"
      }

      l = l |> Lattice.apply_claims(aclaims) |> Lattice.apply_claims(vclaims)

      hb =
        CloudEvents.host_heartbeat(
          "Nxxxx",
          %{foo: "bar", baz: "biz"},
          %{"Mxxxx" => 1},
          [
            %{
              "link_name" => "default",
              "public_key" => "Vxxxx"
            }
          ]
        )

      # NOTE - claims arrived first, got cached, then heartbeat arrived with no metadata
      # about providers or actors, lattice observer augmented from the cache.
      l = l |> Lattice.apply_event(hb)
      assert Map.get(l.providers, {"Vxxxx", "default"}).name == "Super ultra mega provider"
      assert Map.get(l.actors, "Mxxxx").call_alias == "test/bob"
    end
  end
end
