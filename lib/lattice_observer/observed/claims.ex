defmodule LatticeObserver.Observed.Claims do
  require Logger
  alias __MODULE__
  alias LatticeObserver.Observed.{Lattice, Provider, Actor}

  @enforce_keys [:sub, :iss]
  defstruct [
    :sub,
    :call_alias,
    :iss,
    :name,
    :caps,
    :rev,
    :tags,
    :version
  ]

  @type t :: %Claims{
          sub: String.t(),
          call_alias: String.t(),
          iss: String.t(),
          name: String.t(),
          # Comma-delimited list
          caps: String.t(),
          rev: String.t(),
          # Comma-delimited list
          tags: String.t(),
          version: String.t()
        }

  # Apply a capability provider's claims
  @spec apply(Lattice.t(), Claims.t()) :: Lattice.t()
  def apply(
        l = %Lattice{},
        claims = %Claims{
          sub: public_key = "V" <> _rest,
          iss: issuer,
          name: name,
          tags: tags
        }
      ) do
    l = %Lattice{l | claims: l.claims |> Map.put(public_key, claims)}

    provs =
      l.providers
      |> Enum.map(fn {key = {pk, _ln}, prov} ->
        if public_key == pk do
          {key, %Provider{prov | name: name, issuer: issuer, tags: tags |> String.split(",")}}
        else
          {key, prov}
        end
      end)
      |> Enum.into(%{})

    %Lattice{l | providers: provs}
  end

  # Apply an actor's claims
  def apply(
        l = %Lattice{},
        claims = %Claims{
          sub: public_key = "M" <> _rest,
          iss: issuer,
          name: name,
          caps: caps,
          call_alias: call_alias,
          tags: tags
        }
      ) do
    l = %Lattice{l | claims: l.claims |> Map.put(public_key, claims)}

    l =
      case l.actors |> Map.get(public_key) do
        nil ->
          # Please disperse, nothing to see here.
          l

        a ->
          a = %Actor{
            a
            | name: name,
              capabilities: caps |> String.split(","),
              issuer: issuer,
              call_alias: call_alias,
              tags: tags
          }

          %Lattice{l | actors: l.actors |> Map.put(public_key, a)}
      end

    l
  end

  def apply(l = %Lattice{}, claims = %Claims{}) do
    Logger.warn("Unexpected claims data: #{inspect(claims)}")
    l
  end
end
