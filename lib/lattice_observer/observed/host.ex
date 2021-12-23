defmodule LatticeObserver.Observed.Host do
  alias __MODULE__

  @enforce_keys [:id, :labels]
  defstruct [:id, :labels, :status, :last_seen, :first_seen, :friendly_name]

  @typedoc """
  Represents a host observed through heartbeat and start events within a lattice
  """
  @type t :: %Host{
          id: String.t(),
          labels: Map.t(),
          status: LatticeObserver.Observed.Lattice.entitystatus(),
          last_seen: Datetime.t(),
          first_seen: Datetime.t(),
          friendly_name: String.t()
        }
end
