defmodule LatticeObserver.Observed.Lattice do
  @annotation_app_spec "wasmcloud.dev/appspec"

  @moduledoc """
  The root structure of an observed lattice. An observed lattice is essentially an
  event sourced aggregate who state is determined by application of a stream of
  lattice events
  """
  alias __MODULE__
  alias LatticeObserver.Observed.{Provider, Host, Instance, LinkDefinition}

  require Logger

  # We need the keys to be there, even if they hold empty lists
  @enforce_keys [:actors, :providers, :hosts, :linkdefs]
  defstruct [:actors, :providers, :hosts, :linkdefs, :refmap, :instance_tracking]

  @typedoc """
  A provider key is the provider's public key accompanied by the link name
  """
  @type provider_key :: {String.t(), String.t()}

  @type actormap :: %{required(String.t()) => [Instance.t()]}
  @type providermap :: %{required(provider_key()) => Provider.t()}
  @type hostmap :: %{required(String.t()) => Host.t()}
  # map between OCI image URL/imageref and public key
  @type refmap :: %{required(String.t()) => String.t()}

  @typedoc """
  Keys are the instance ID, values are ISO 8601 timestamps in UTC
  """
  @type instance_trackmap :: %{required(String.t()) => DateTime.t()}

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
          refmap: refmap()
        }

  @spec new :: t()
  def new() do
    %Lattice{
      actors: %{},
      providers: %{},
      hosts: %{},
      linkdefs: [],
      instance_tracking: %{},
      refmap: %{}
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
          data: %{"actors" => _actors, "providers" => _providers, "labels" => labels},
          datacontenttype: "application/json",
          source: source_host,
          time: stamp,
          type: "com.wasmcloud.lattice.host_heartbeat"
        }
      ) do
    record_host(l, source_host, labels, stamp)
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data: %{
            "public_key" => _public_key,
            "link_name" => _link_name,
            "annotations" => _annotations
          },
          datacontenttype: "application/json",
          source: _source_host,
          type: "com.wasmcloud.lattice.health_check_passed"
        }
      ) do
    l
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data: %{
            "public_key" => _public_key,
            "link_name" => _link_name,
            "annotations" => _annotations
          },
          datacontenttype: "application/json",
          source: _source_host,
          type: "com.wasmcloud.lattice.health_check_failed"
        }
      ) do
    l
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data: %{
            "public_key" => pk,
            "link_name" => link_name,
            "contract_id" => contract_id,
            "instance_id" => instance_id,
            "annotations" => %{
              @annotation_app_spec => spec
            }
          },
          time: stamp,
          source: source_host,
          datacontenttype: "application/json",
          type: "com.wasmcloud.lattice.provider_started"
        }
      ) do
    put_provider_instance(l, source_host, pk, link_name, contract_id, instance_id, spec, stamp)
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data: %{
            "link_name" => link_name,
            "public_key" => pk,
            "instance_id" => instance_id,
            "annotations" => %{
              @annotation_app_spec => spec
            }
          },
          datacontenttype: "application/json",
          source: source_host,
          time: _stamp,
          type: "com.wasmcloud.lattice.provider_stopped"
        }
      ) do
    remove_provider_instance(l, source_host, pk, link_name, instance_id, spec)
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data: %{
            "public_key" => pk,
            "instance_id" => instance_id,
            "annotations" => %{
              @annotation_app_spec => spec
            }
          },
          datacontenttype: "application/json",
          source: source_host,
          type: "com.wasmcloud.lattice.actor_stopped"
        }
      ) do
    remove_actor_instance(l, source_host, pk, instance_id, spec)
  end

  def apply_event(
        l = %Lattice{},
        %Cloudevents.Format.V_1_0.Event{
          data: %{
            "public_key" => pk,
            "instance_id" => instance_id,
            "annotations" => %{
              @annotation_app_spec => spec
            }
          },
          source: source_host,
          datacontenttype: "application/json",
          time: stamp,
          type: "com.wasmcloud.lattice.actor_started"
        }
      ) do
    put_actor_instance(l, source_host, pk, instance_id, spec, stamp)
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
          type: "com.wasmcloud.lattice.linkdef_put"
        }
      ) do
    put_linkdef(l, actor_id, link_name, provider_id, contract_id, values)
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
          type: "com.wasmcloud.lattice.linkdef_del"
        }
      ) do
    del_linkdef(l, actor_id, link_name, provider_id)
  end

  def apply_event(l = %Lattice{}, %Cloudevents.Format.V_1_0.Event{
        data: %{
          "image_ref" => image_ref,
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
          "image_ref" => image_ref
        },
        source: _source_host,
        datacontenttype: "application/json",
        type: "com.wasmcloud.lattice.refmap_del"
      }) do
    %Lattice{l | refmap: Map.delete(l.refmap, image_ref)}
  end

  def apply_event(l = %Lattice{}, evt) do
    Logger.warn("Unexpected event: #{inspect(evt)}")
    l
  end

  defp put_linkdef(l = %Lattice{}, actor_id, link_name, provider_id, contract_id, values) do
    case Enum.find(l.linkdefs, fn link ->
           link.actor_id == actor_id && link.provider_id == provider_id &&
             link.link_name == link_name
         end) do
      nil ->
        ld = %LinkDefinition{
          actor_id: actor_id,
          link_name: link_name,
          provider_id: provider_id,
          contract_id: contract_id,
          values: values
        }

        %Lattice{l | linkdefs: [ld | l.linkdefs]}

      _ ->
        l
    end
  end

  defp del_linkdef(l = %Lattice{}, actor_id, link_name, provider_id) do
    %Lattice{
      l
      | linkdefs:
          Enum.reject(l.linkdefs, fn link ->
            link.actor_id == actor_id && link.link_name == link_name &&
              link.provider_id == provider_id
          end)
    }
  end

  defp remove_actor_instance(l = %Lattice{}, host_id, pk, instance_id, spec) do
    instances = Map.get(l.actors, pk, [])

    instance = %Instance{
      id: instance_id,
      host_id: host_id,
      spec_id: spec
    }

    actor_instances = Enum.reject(instances, fn tgt_instance -> instance == tgt_instance end)
    l = %Lattice{l | actors: Map.put(l.actors, pk, actor_instances)}
    %Lattice{l | instance_tracking: Map.delete(l.instance_tracking, instance.id)}
  end

  defp put_actor_instance(l = %Lattice{}, host_id, pk, instance_id, spec, stamp)
       when is_binary(pk) and is_binary(instance_id) and is_binary(spec) do
    instances = Map.get(l.actors, pk, [])

    instance = %Instance{
      id: instance_id,
      host_id: host_id,
      spec_id: spec
    }

    actor_instances =
      if Enum.member?(instances, instance) do
        instances
      else
        [instance | instances]
      end

    %Lattice{
      l
      | actors: Map.put(l.actors, pk, actor_instances),
        instance_tracking:
          Map.put(l.instance_tracking, instance.id, timestamp_from_iso8601(stamp))
    }
  end

  defp put_provider_instance(
         l = %Lattice{},
         source_host,
         pk,
         link_name,
         contract_id,
         instance_id,
         spec,
         stamp
       ) do
    provider = Map.get(l.providers, {pk, link_name}, Provider.new(pk, link_name, contract_id))
    instances = provider.instances

    instance = %Instance{
      id: instance_id,
      host_id: source_host,
      spec_id: spec
    }

    prov_instances =
      if Enum.member?(instances, instance) do
        instances
      else
        [instance | instances]
      end

    provider = %{provider | instances: prov_instances}

    %Lattice{
      l
      | providers: Map.put(l.providers, {pk, link_name}, provider),
        instance_tracking:
          Map.put(l.instance_tracking, instance.id, timestamp_from_iso8601(stamp))
    }
  end

  defp remove_provider_instance(l, source_host, pk, link_name, instance_id, spec) do
    provider = Map.get(l.providers, {pk, link_name})

    instance = %Instance{
      id: instance_id,
      host_id: source_host,
      spec_id: spec
    }

    if provider == nil do
      l
    else
      provider_instances =
        Enum.reject(provider.instances, fn tgt_instance -> instance == tgt_instance end)

      provider = %Provider{provider | instances: provider_instances}

      %Lattice{
        l
        | providers: Map.put(l.providers, {pk, link_name}, provider),
          instance_tracking: Map.delete(l.instance_tracking, instance.id)
      }
    end
  end

  defp record_host(l = %Lattice{}, source_host, labels, stamp) do
    host = %Host{
      id: source_host,
      labels: labels,
      last_seen: timestamp_from_iso8601(stamp)
    }

    %Lattice{l | hosts: Map.put(l.hosts, source_host, host)}
  end

  @spec timestamp_from_iso8601(binary) :: DateTime.t()
  def timestamp_from_iso8601(stamp) when is_binary(stamp) do
    case DateTime.from_iso8601(stamp) do
      {:ok, datetime, 0} -> datetime
      _ -> DateTime.utc_now()
    end
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
    for {pk, instances} <- actors,
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

  def providers_in_appspec(%Lattice{}, _appspec) do
    []
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

  defp in_spec?(%Instance{spec_id: spec_id}, appspec) do
    spec_id == appspec
  end
end
