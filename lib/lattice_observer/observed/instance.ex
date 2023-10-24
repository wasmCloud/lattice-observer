defmodule LatticeObserver.Observed.Instance do
  alias __MODULE__

  @enforce_keys [:id, :host_id, :annotations]
  defstruct [:id, :host_id, :annotations, :version, :revision]

  @typedoc """
  An instance represents an observation of a unit of scalability within the lattice. Instances
  have unique IDs (GUIDs) and are stored along with the host on which they exist and the ID of
  the specification (`AppSpec` model) responsible for that instance. Actors and Capability Providers
  both have instances while link definitions do not.
  """
  @type t :: %Instance{
          id: binary(),
          host_id: binary(),
          annotations: map(),
          version: binary(),
          revision: integer()
        }
end
