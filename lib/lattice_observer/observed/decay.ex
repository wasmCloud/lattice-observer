defmodule LatticeObserver.Observed.Decay do
  alias LatticeObserver.Observed.{Lattice, Host}

  @decay_states [:healthy, :warn, :fail, :unavailable]

  # Based on the decay rate in the lattice parameter, hosts should
  # age out in descending order of health status
  def age_hosts(l = %Lattice{}, event_time) do
    {fully_decayed, hosts} =
      age_hosts(l.hosts, event_time, l.parameters.host_status_decay_rate_seconds)

    # Remove each fully decayed host and its resources from the lattice
    lattice =
      List.foldl(fully_decayed, l, fn {hk, _host}, lattice ->
        LatticeObserver.Observed.EventProcessor.remove_host(lattice, hk)
      end)

    # Return the lattice with the list of hosts with updated decay states
    %Lattice{
      lattice
      | hosts: hosts |> Enum.into(%{})
    }
  end

  # Returns a tuple with two elements, the first is a list of hosts that have fully
  # decayed and are removed from the lattice, the second is the new list of hosts
  @spec age_hosts(Lattice.hostmap(), DateTime.t(), Integer.t()) :: {list(), list()}
  defp age_hosts(hosts, event_time, decay_rate) do
    hosts
    |> Enum.map(fn {hk, host} -> {hk, age_host(host, event_time, decay_rate)} end)
    |> Enum.split_with(fn {_hk, host} -> host.status == :remove end)
  end

  @spec age_host(Host.t(), DateTime.t(), Integer.t()) :: Host.t()
  defp age_host(host, event_time, decay_rate) do
    gapfactor = div(DateTime.diff(event_time, host.last_seen), decay_rate)

    %Host{
      host
      | status:
          if gapfactor > length(@decay_states) - 1 do
            :remove
          else
            Enum.at(@decay_states, gapfactor)
          end
    }
  end
end
