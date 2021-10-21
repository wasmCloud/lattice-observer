defmodule LatticeObserver.SubscriptionServer do
  require Logger
  use Gnat.Server

  def request(%{topic: topic, body: body}) do
    prefix =
      topic
      |> String.split(".")
      |> Enum.at(2)

    event = Jason.decode!(body)

    Registry.dispatch(Registry.LatticeObserverRegistry, prefix, fn entries ->
      for {pid, _} <- entries, do: GenServer.cast(pid, {:handle_event, event})
    end)

    :ok
  end
end
