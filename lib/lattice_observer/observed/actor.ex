defmodule LatticeObserver.Observed.Actor do
  alias __MODULE__
  alias LatticeObserver.Observed.Instance

  @enforce_keys [:id, :name, :instances]
  defstruct [:id, :name, :capabilities, :issuer, :tags, :call_alias, :instances]

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

  def new(id, name) when is_binary(id) and is_binary(name) do
    %Actor{
      id: id,
      name: name,
      instances: []
    }
  end
end
