defmodule LatticeObserver.Observed.Lattice do
  @annotation_app_spec "wasmcloud.dev/appspec"

  @moduledoc """
  The root structure of an observed lattice. An observed lattice is essentially an
  event sourced aggregate who state is determined by application of a stream of
  lattice events
  """
  alias __MODULE__

  alias LatticeObserver.Observed.{
    Provider,
    Host,
    Actor,
    Instance,
    LinkDefinition,
    Decay,
    EventProcessor,
    Invocation
  }

  require Logger

  # We need the keys to be there, even if they hold empty lists
  @enforce_keys [:actors, :providers, :hosts, :linkdefs]
  defstruct [
    :actors,
    :providers,
    :hosts,
    :linkdefs,
    :refmap,
    :instance_tracking,
    :parameters,
    :invocation_log
  ]

  @typedoc """
  A provider key is the provider's public key accompanied by the link name
  """
  @type provider_key :: {String.t(), String.t()}

  @type actormap :: %{required(String.t()) => [Actor.t()]}
  @type providermap :: %{required(provider_key()) => Provider.t()}
  @type hostmap :: %{required(String.t()) => Host.t()}
  # map between OCI image URL/imageref and public key
  @type refmap :: %{required(String.t()) => String.t()}

  @type entitystatus :: :healthy | :warn | :fail | :unavailable | :remove

  @typedoc """
  Keys are the instance ID, values are ISO 8601 timestamps in UTC
  """
  @type instance_trackmap :: %{required(String.t()) => DateTime.t()}

  defmodule Parameters do
    @type t :: %Parameters{
            host_status_decay_rate_seconds: Integer.t()
          }
    defstruct [:host_status_decay_rate_seconds]
  end

  @typedoc """
  The root structure of an observed lattice. An observed lattice keeps track
  of the actors, providers, link definitions, and hosts within it.
  """
  @type t :: %Lattice{
          actors: actormap(),
          providers: providermap(),
          hosts: hostmap(),
          linkdefs: [LinkDefinition.t()],
          instance_tracking: instance_trackmap(),
          refmap: refmap(),
          invocation_log: Invocation.invocationlog_map(),
          parameters: [Parameters.t()]
        }

  @spec new(Keyword.t()) :: LatticeObserver.Observed.Lattice.t()
  def new(parameters \\ []) do
    %Lattice{
      actors: %{},
      providers: %{},
      hosts: %{},
      linkdefs: [],
      instance_tracking: %{},
      refmap: %{},
      invocation_log: %{},
      parameters: %Parameters{
        host_status_decay_rate_seconds:
          Keyword.get(parameters, :host_status_decay_rate_seconds, 35)
      }
    }
  end

  # Note to those unfamiliar with Elixir matching syntax. The following function
  # patterns are not "complete" or "exact" matches. They only match the _minimum_ required shape of
  # the event in question. Events can have more fields with which the pattern isn't
  # concerned and the pattern match will still be successful. Where possible, we've tried to use
  # ignored variables to indicate required fields that aren't used for internal processing.

  @spec apply_event(
          t(),
          Cloudevents.Format.V_1_0.Event.t()
        ) :: t()
  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data: data,
          datacontenttype: "application/json",
          source: source_host,
          time: stamp,
          type: "com.wasmcloud.lattice.host_heartbeat"
        }
      ) do
    EventProcessor.record_heartbeat(l, source_host, stamp, data)
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data: data,
          datacontenttype: "application/json",
          source: source_host,
          time: stamp,
          type: "com.wasmcloud.lattice.host_started"
        }
      ) do
    labels = Map.get(data, "labels", %{})
    friendly_name = Map.get(data, "friendly_name", "")
    EventProcessor.record_host(l, source_host, labels, stamp, friendly_name)
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          datacontenttype: "application/json",
          source: _source_host,
          type: "com.wasmcloud.lattice.invocation_succeeded",
          data: %{
            "source" =>
              %{
                "public_key" => _pk,
                "contract_id" => _cid,
                "link_name" => _ln
              } = source,
            "dest" =>
              %{
                "public_key" => _pk2,
                "contract_id" => _cid2,
                "link_name" => _ln2
              } = dest,
            "operation" => operation,
            "bytes" => bytes
          }
        }
      ) do
    Invocation.record_invocation_success(l, source, dest, operation, bytes)
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          datacontenttype: "application/json",
          source: _source_host,
          type: "com.wasmcloud.lattice.invocation_failed",
          data: %{
            "source" =>
              %{
                "public_key" => _pk,
                "contract_id" => _cid,
                "link_name" => _ln
              } = source,
            "dest" =>
              %{
                "public_key" => _pk2,
                "contract_id" => _cid2,
                "link_name" => _ln2
              } = dest,
            "operation" => operation,
            "bytes" => bytes
          }
        }
      ) do
    Invocation.record_invocation_failed(l, source, dest, operation, bytes)
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          datacontenttype: "application/json",
          source: source_host,
          type: "com.wasmcloud.lattice.host_stopped"
        }
      ) do
    EventProcessor.remove_host(l, source_host)
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data: %{
            "public_key" => _public_key
          },
          datacontenttype: "application/json",
          source: _source_host,
          type: "com.wasmcloud.lattice.health_check_passed"
        }
      ) do
    # TODO update the status of entity that passed check
    l
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data: %{
            "public_key" => _public_key
          },
          datacontenttype: "application/json",
          source: _source_host,
          type: "com.wasmcloud.lattice.health_check_failed"
        }
      ) do
    # TODO update status of entity that failed check
    l
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data:
            %{
              "public_key" => pk,
              "link_name" => link_name,
              "contract_id" => contract_id,
              "instance_id" => instance_id
            } = d,
          time: stamp,
          source: source_host,
          datacontenttype: "application/json",
          type: "com.wasmcloud.lattice.provider_started"
        }
      ) do
    annotations = Map.get(d, "annotations", %{})
    spec = Map.get(annotations, @annotation_app_spec, "")
    claims = Map.get(d, "claims", %{})

    EventProcessor.put_provider_instance(
      l,
      source_host,
      pk,
      link_name,
      contract_id,
      instance_id,
      spec,
      stamp,
      claims
    )
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          source: _source_host,
          datacontenttype: "application/json",
          time: _stamp,
          type: "com.wasmcloud.lattice.provider_start_failed"
        }
      ) do
    # This does not currently affect state, but shouldn't generate a warning either
    l
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data:
            %{
              "link_name" => link_name,
              "public_key" => pk,
              "instance_id" => instance_id
            } = d,
          datacontenttype: "application/json",
          source: source_host,
          time: _stamp,
          type: "com.wasmcloud.lattice.provider_stopped"
        }
      ) do
    annotations = Map.get(d, "annotations", %{})
    spec = Map.get(annotations, @annotation_app_spec, "")
    EventProcessor.remove_provider_instance(l, source_host, pk, link_name, instance_id, spec)
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data:
            %{
              "public_key" => pk,
              "instance_id" => instance_id
            } = d,
          datacontenttype: "application/json",
          source: source_host,
          type: "com.wasmcloud.lattice.actor_stopped"
        }
      ) do
    spec = Map.get(d, "annotations", %{}) |> Map.get(@annotation_app_spec, "")
    EventProcessor.remove_actor_instance(l, source_host, pk, instance_id, spec)
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data:
            %{
              "public_key" => pk,
              "instance_id" => instance_id
            } = d,
          source: source_host,
          datacontenttype: "application/json",
          time: stamp,
          type: "com.wasmcloud.lattice.actor_started"
        }
      ) do
    spec = Map.get(d, "annotations", %{}) |> Map.get(@annotation_app_spec, "")
    claims = Map.get(d, "claims", %{})
    EventProcessor.put_actor_instance(l, source_host, pk, instance_id, spec, stamp, claims)
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          source: _source_host,
          datacontenttype: "application/json",
          time: _stamp,
          type: "com.wasmcloud.lattice.actor_start_failed"
        }
      ) do
    # This does not currently affect state, but shouldn't generate a warning either
    l
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data: %{
            "actor_id" => actor_id,
            "link_name" => link_name,
            "contract_id" => contract_id,
            "provider_id" => provider_id,
            "values" => values
          },
          source: _source_host,
          datacontenttype: "application/json",
          type: "com.wasmcloud.lattice.linkdef_set"
        }
      ) do
    EventProcessor.put_linkdef(l, actor_id, link_name, provider_id, contract_id, values)
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data: %{
            "actor_id" => actor_id,
            "link_name" => link_name,
            "provider_id" => provider_id,
            "contract_id" => _contract_id
          },
          source: _source_host,
          datacontenttype: "application/json",
          type: "com.wasmcloud.lattice.linkdef_deleted"
        }
      ) do
    EventProcessor.del_linkdef(l, actor_id, link_name, provider_id)
  end

  def apply_event(l = %Lattice{}, %Cloudevents.Format.V_1_0.Event{
        data: %{
          "oci_url" => image_ref,
          "public_key" => public_key
        },
        source: _source_host,
        datacontenttype: "application/json",
        type: "com.wasmcloud.lattice.refmap_set"
      }) do
    %Lattice{l | refmap: Map.put(l.refmap, image_ref, public_key)}
  end

  def apply_event(l = %Lattice{}, %Cloudevents.Format.V_1_0.Event{
        data: %{
          "oci_url" => image_ref
        },
        source: _source_host,
        datacontenttype: "application/json",
        type: "com.wasmcloud.lattice.refmap_del"
      }) do
    %Lattice{l | refmap: Map.delete(l.refmap, image_ref)}
  end

  def apply_event(l = %Lattice{}, %Cloudevents.Format.V_1_0.Event{
        source: _source_host,
        datacontenttype: "application/json",
        type: "com.wasmcloud.synthetic.decay_ticked",
        time: stamp
      }) do
    event_time = EventProcessor.timestamp_from_iso8601(stamp)
    Decay.age_hosts(l, event_time)
  end

  def apply_event(l = %Lattice{}, evt) do
    Logger.warn("Unexpected event: #{inspect(evt)}")
    l
  end

  @spec running_instances(
          LatticeObserver.Observed.Lattice.t(),
          nil | String.t(),
          String.t()
        ) :: [%{id: String.t(), instance_id: String.t(), host_id: String.t()}]
  def running_instances(%Lattice{} = l, pk, spec_id) when is_binary(pk) do
    if String.starts_with?(pk, "M") do
      actors_in_appspec(l, spec_id)
      |> Enum.map(fn %{actor_id: pk, instance_id: iid, host_id: hid} ->
        %{id: pk, instance_id: iid, host_id: hid}
      end)
    else
      providers_in_appspec(l, spec_id)
      |> Enum.map(fn %{provider_id: pk, instance_id: iid, host_id: hid} ->
        %{id: pk, instance_id: iid, host_id: hid}
      end)
    end
  end

  def running_instances(%Lattice{}, nil, _spec_id) do
    []
  end

  @spec actors_in_appspec(LatticeObserver.Observed.Lattice.t(), binary) :: [
          %{actor_id: String.t(), instance_id: String.t(), host_id: String.t()}
        ]
  def actors_in_appspec(%Lattice{actors: actors}, appspec) when is_binary(appspec) do
    for {pk, %Actor{instances: instances}} <- actors,
        instance <- instances,
        in_spec?(instance, appspec) do
      %{
        actor_id: pk,
        instance_id: instance.id,
        host_id: instance.host_id
      }
    end
  end

  @spec providers_in_appspec(LatticeObserver.Observed.Lattice.t(), binary) :: [
          %{
            provider_id: String.t(),
            link_name: String.t(),
            host_id: String.t(),
            instance_id: String.t()
          }
        ]
  def providers_in_appspec(%Lattice{providers: providers}, appspec) when is_binary(appspec) do
    for {{pk, link_name}, %Provider{instances: instances, contract_id: contract_id}} <- providers,
        instance <- instances,
        in_spec?(instance, appspec) do
      %{
        provider_id: pk,
        link_name: link_name,
        contract_id: contract_id,
        host_id: instance.host_id,
        instance_id: instance.id
      }
    end
  end

  def lookup_linkdef(%Lattice{linkdefs: linkdefs}, actor_id, provider_id, link_name) do
    case Enum.filter(linkdefs, fn ld ->
           ld.actor_id == actor_id && ld.provider_id == provider_id && ld.link_name == link_name
         end) do
      [h | _] -> {:ok, h}
      [] -> :error
    end
  end

  def lookup_ociref(%Lattice{refmap: refmap}, target) when is_binary(target) do
    case Map.get(refmap, target) do
      nil -> :error
      pk -> {:ok, pk}
    end
  end

  @spec lookup_invocation_log(
          Lattice.t(),
          Invocation.Entity.t(),
          Invocation.Entity.t(),
          String.t()
        ) ::
          :error | {:ok, Invocation.Log.t()}
  def lookup_invocation_log(%Lattice{invocation_log: log}, from, to, operation) do
    case Map.get(log, {from, to, operation}) do
      nil -> :error
      il -> {:ok, il}
    end
  end

  @spec get_all_invocation_logs(Lattice.t()) :: [Invocation.InvocationLog.t()]
  def get_all_invocation_logs(%Lattice{} = l) do
    Map.values(l.invocation_log)
  end

  defp in_spec?(%Instance{spec_id: spec_id}, appspec) do
    spec_id == appspec
  end
end
