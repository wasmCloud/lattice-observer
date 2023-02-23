defmodule LatticeObserver.Observed.Provider do
  alias __MODULE__
  alias LatticeObserver.Observed.Instance

  @enforce_keys [:id, :contract_id, :link_name, :instances]
  defstruct [:id, :name, :issuer, :contract_id, :tags, :link_name, :instances]

  @typedoc """
  A representation of an observed capability provider. Providers are uniquely
  defined by their public ID and contract ID. Instances of the capability provider
  are tracked in the same way as actor instances.
  """
  @type t :: %Provider{
          id: binary(),
          name: binary(),
          issuer: binary(),
          contract_id: binary(),
          tags: binary(),
          link_name: binary(),
          instances: [Instance.t()]
        }

  def new(id, link_name, contract_id, instances \\ [], tags \\ []) do
    %Provider{
      id: id,
      link_name: link_name,
      contract_id: contract_id,
      instances: instances,
      tags: tags
    }
  end
end
