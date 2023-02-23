defmodule LatticeObserver.Observed.Host do
  alias __MODULE__

  @enforce_keys [:id, :labels]
  defstruct [
    :id,
    :labels,
    :status,
    :last_seen,
    :first_seen,
    :friendly_name,
    :uptime_seconds,
    :version
  ]

  @typedoc """
  Represents a host observed through heartbeat and start events within a lattice
  """
  @type t :: %Host{
          id: binary(),
          labels: map(),
          status: LatticeObserver.Observed.Lattice.entitystatus(),
          last_seen: DateTime.t(),
          first_seen: DateTime.t(),
          friendly_name: binary(),
          uptime_seconds: non_neg_integer(),
          version: binary()
        }
end
