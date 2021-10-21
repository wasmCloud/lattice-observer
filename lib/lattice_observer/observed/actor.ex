defmodule LatticeObserver.Observed.Actor do
  alias __MODULE__
  alias LatticeObserver.Observed.Instance

  @enforce_keys [:id, :instances]
  defstruct [:id, :instances]

  @typedoc """
  An actor observed through event receipt within the lattice.
  """
  @type t :: %Actor{
          id: String.t(),
          instances: [Instance.t()]
        }
end
