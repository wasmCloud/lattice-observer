defmodule LatticeObserver.Observed.Invocation do
  alias LatticeObserver.Observed.Lattice
  alias __MODULE__.Entity

  @type invocationlog_key :: {from :: Entity.t(), to :: Entity.t(), operation :: String.t()}
  @type invocationlog_map :: %{required(invocationlog_key()) => InvocationLog.t()}

  defmodule InvocationLog do
    @type t :: %InvocationLog{
            from: Entity.t(),
            to: Entity.t(),
            operation: String.t(),
            total_bytes: Integer.t(),
            fail_count: Integer.t(),
            success_count: Integer.t()
          }

    defstruct [:from, :to, :operation, :total_bytes, :fail_count, :success_count]

    def from_key({from, to, operation}) do
      %InvocationLog{
        from: from,
        to: to,
        operation: operation,
        total_bytes: 0,
        fail_count: 0,
        success_count: 0
      }
    end
  end

  defmodule Entity do
    @type t :: %Entity{
            public_key: String.t(),
            link_name: String.t() | nil,
            contract_id: String.t() | nil
          }
    defstruct [:public_key, :link_name, :contract_id]

    def from_event_entity(entity) do
      %Entity{
        public_key: Map.get(entity, "public_key"),
        link_name: Map.get(entity, "link_name") |> nillify_empty(),
        contract_id: Map.get(entity, "contract_id") |> nillify_empty()
      }
    end

    defp nillify_empty(nil), do: nil

    defp nillify_empty(str) do
      if String.trim(str) == "" do
        nil
      else
        str
      end
    end
  end

  @spec record_invocation_success(
          Lattice.t(),
          source :: Map.t(),
          dest :: Map.t(),
          operation :: String.t(),
          Integer.t()
        ) ::
          Lattice.t()
  def record_invocation_success(l = %Lattice{}, source, dest, operation, bytes) do
    key = {source |> Entity.from_event_entity(), dest |> Entity.from_event_entity(), operation}
    old_log = Map.get(l.invocation_log, key, key |> InvocationLog.from_key())

    log = %InvocationLog{
      old_log
      | total_bytes: old_log.total_bytes + bytes,
        success_count: old_log.success_count + 1
    }

    %Lattice{
      l
      | invocation_log: Map.put(l.invocation_log, key, log)
    }
  end

  @spec record_invocation_failed(
          Lattice.t(),
          source :: Map.t(),
          dest :: Map.t(),
          operation :: String.t(),
          Integer.t()
        ) ::
          Lattice.t()
  def record_invocation_failed(l = %Lattice{}, source, dest, operation, bytes) do
    key = {source |> Entity.from_event_entity(), dest |> Entity.from_event_entity(), operation}
    old_log = Map.get(l.invocation_log, key, key |> InvocationLog.from_key())

    log = %InvocationLog{
      old_log
      | total_bytes: old_log.total_bytes + bytes,
        fail_count: old_log.fail_count + 1
    }

    %Lattice{
      l
      | invocation_log: Map.put(l.invocation_log, key, log)
    }
  end
end
