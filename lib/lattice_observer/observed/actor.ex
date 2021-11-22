defmodule LatticeObserver.Observed.Actor do
  alias __MODULE__
  alias LatticeObserver.Observed.Instance

  @enforce_keys [:id, :name]
  defstruct [:id, :name, :capabilities, :issuer, :tags, :call_alias, :version, :instances]

  @typedoc """
  An actor observed through event receipt within the lattice.
  """
  @type t :: %Actor{
          id: String.t(),
          name: String.t(),
          capabilities: [String.t()],
          issuer: String.t(),
          tags: String.t(),
          call_alias: String.t(),
          instances: [Instance.t()]
        }
end
