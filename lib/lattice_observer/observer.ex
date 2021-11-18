defmodule LatticeObserver.Observer do
  require Logger

  @callback state_changed(
              old_state :: LatticeObserver.Observed.Lattice.t(),
              new_state :: LatticeObserver.Observed.Lattice.t(),
              event :: term,
              lattice_prefix :: String.t()
            ) :: :ok

  defmacro __using__(_opts) do
    quote do
      @behaviour LatticeObserver.Observer
    end
  end

  def execute(module, old_state, new_state, event, lattice_prefix) do
    try do
      apply(module, :state_changed, [old_state, new_state, event, lattice_prefix])
    rescue
      e ->
        Logger.error("Failed to invoke #{module} state changed callback: #{e}")
    end
  end
end
