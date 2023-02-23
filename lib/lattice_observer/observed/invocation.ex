defmodule LatticeObserver.Observed.Invocation do
  alias LatticeObserver.Observed.Lattice
  alias __MODULE__.Entity

  defmodule InvocationLog do
    @type t :: %InvocationLog{
            from: Entity.t(),
            to: Entity.t(),
            operation: binary(),
            total_bytes: integer(),
            fail_count: integer(),
            success_count: integer()
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
            public_key: binary(),
            link_name: binary() | nil,
            contract_id: binary() | nil
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

  @type invocationlog_key :: {from :: Entity.t(), to :: Entity.t(), operation :: binary()}
  @type invocationlog_map :: %{required(invocationlog_key()) => InvocationLog.t()}

  @spec record_invocation_success(
          Lattice.t(),
          source :: map(),
          dest :: map(),
          operation :: binary(),
          integer()
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
          source :: map(),
          dest :: map(),
          operation :: binary(),
          integer()
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
