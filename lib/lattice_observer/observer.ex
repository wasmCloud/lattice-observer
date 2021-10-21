defmodule LatticeObserver.Observer do
  require Logger

  @callback state_changed(state :: LatticeObserver.Observed.Lattice.t()) :: :ok

  defmacro __using__(_opts) do
    quote do
      @behaviour LatticeObserver.Observer
    end
  end

  @doc false
  def execute(module, state) do
    try do
      apply(module, :state_changed, state)
    rescue
      e ->
        Logger.error("Failed to invoke #{module} state changed callback: #{e}")
    end
  end
end
