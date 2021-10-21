defmodule LatticeObserver.NatsObserver do
  use GenServer
  require Logger

  def start_link(settings, options \\ []) do
    GenServer.start_link(__MODULE__, settings, options)
  end

  @impl GenServer
  def init(settings) do
    # TODO enforce mandatory settings
    cs_settings = %{
      connection_name: Map.get(settings, :supervised_connection),
      module: LatticeObserver.SubscriptionServer,
      subscription_topics: [
        %{
          topic: "wasmbus.evt.#{settings.lattice_prefix}"
        }
      ]
    }

    Registry.register(Registry.LatticeObserverRegistry, settings.lattice_prefix, [])

    {:ok, _super} = Gnat.ConsumerSupervisor.start_link(cs_settings, [])

    state = %{
      lc: LatticeObserver.Observed.Lattice.new(),
      lattice_prefix: Map.get(settings, :lattice_prefix),
      module: Map.get(settings, :module)
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:handle_event, event}, state) do
    nstate = %{state | lc: LatticeObserver.Observed.Lattice.apply_event(state.lc, event)}

    if nstate != state do
      LatticeObserver.Observer.execute(state.module, state.lc)
    end

    {:noreply, nstate}
  end
end
