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
      lc: LatticeObserver.Observed.Lattice.new(Map.get(settings, :lattice_parameters, [])),
      lattice_prefix: Map.get(settings, :lattice_prefix),
      module: Map.get(settings, :module)
    }

    {:ok, state}
  end

  @spec get_prefix(pid) :: String.t()
  def get_prefix(pid) do
    GenServer.call(pid, :get_prefix)
  end

  @spec get_hosts(pid) :: [LatticeObserver.Observed.Host.t()]
  def get_hosts(pid) do
    GenServer.call(pid, :get_hosts)
  end

  @spec get_observed_lattice(pid) :: LatticeObserver.Observed.Lattice.t()
  def get_observed_lattice(pid) do
    GenServer.call(pid, :get_lattice)
  end

  @doc """
  Instructs the lattice observer to self-inject a decay tick, evaluating
  the age of various observed entities against the lattice's decay parameters
  """
  def do_decay(pid) do
    GenServer.cast(pid, :do_decay)
  end

  @impl true
  def handle_cast({:handle_event, event}, state) do
    case Cloudevents.from_map(event) do
      {:ok, evt} ->
        Logger.debug("Processing event #{evt.type}")
        nstate = %{state | lc: LatticeObserver.Observed.Lattice.apply_event(state.lc, evt)}

        LatticeObserver.Observer.execute(
          state.module,
          state.lc,
          nstate.lc,
          evt,
          state.lattice_prefix
        )

        {:noreply, nstate}

      {:error, error} ->
        Logger.error("Failed to decode cloud event: #{inspect(error)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:do_decay, state) do
    tick = LatticeObserver.CloudEvent.new_synthetic(%{}, "decay_ticked", "none")

    nstate = %{
      state
      | lc: state.lc |> LatticeObserver.Observed.Lattice.apply_event(tick)
    }

    LatticeObserver.Observer.execute(
      state.module,
      state.lc,
      nstate.lc,
      tick,
      state.lattice_prefix
    )

    {:noreply, nstate}
  end

  @impl true
  def handle_call(:get_lattice, _from, state) do
    {:reply, state.lc, state}
  end

  @impl true
  def handle_call(:get_prefix, _from, state) do
    {:reply, state.lattice_prefix, state}
  end

  @impl true
  def handle_call(:get_hosts, _from, state) do
    {:reply, state.lc.hosts |> Map.values(), state}
  end
end
