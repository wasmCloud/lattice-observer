# Lattice Observer
A reusable Elixir library for monitoring a lattice and deriving observed state.

## Usage
The lattice observer is a `GenServer` supervisor that operates a process tree responsible for reacting to events from a lattice and computing derived state from those events. 

First, you'll want to create a `Gnat.ConnectionSupervisor` with a given name, for example:

```elixir
 Supervisor.child_spec(
        {Gnat.ConnectionSupervisor, nats_connection_options},
        id: :lattice_connection_supervisor
      ),
```

With a running Gnat/NATS connection supervisor, you can then start the NATS lattice observer:

```elixir
{:ok, lattice} = NatsObserver.start_link(
    %{
        supervised_connection: :lattice_connection_supervisor,
        module: MyApp.LatticeWatcher
        lattice_prefix: "default"
    })
```

The `module` argument is the name of a module that must implement the `LatticeObserver.Observer` behavior. This module's `state_changed(state)` function will be invoked when state changes, etc.

For more information, see the hex documentation.