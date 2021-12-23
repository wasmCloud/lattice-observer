defmodule LatticeObserver.Observed.EventProcessor do
  alias LatticeObserver.Observed.{Lattice, Provider, Host, Actor, Instance, LinkDefinition}

  def put_actor_instance(l = %Lattice{}, host_id, pk, instance_id, spec, stamp, claims)
      when is_binary(pk) and is_binary(instance_id) and is_binary(spec) do
    actor =
      Map.get(l.actors, pk, %Actor{
        id: pk,
        name: Map.get(claims, "name", "unavailable"),
        capabilities: Map.get(claims, "caps", []),
        issuer: Map.get(claims, "issuer", ""),
        tags: Map.get(claims, "tags", []),
        call_alias: Map.get(claims, "call_alias", ""),
        instances: []
      })

    instance = %Instance{
      id: instance_id,
      host_id: host_id,
      spec_id: spec,
      version: Map.get(claims, "version", ""),
      revision: Map.get(claims, "revision", 0)
    }

    actor =
      if actor.instances |> Enum.find(fn i -> i.id == instance_id end) == nil do
        %{actor | instances: [instance | actor.instances]}
      else
        actor
      end

    %Lattice{
      l
      | actors: Map.put(l.actors, pk, actor),
        instance_tracking:
          Map.put(l.instance_tracking, instance.id, timestamp_from_iso8601(stamp))
    }
  end

  def put_provider_instance(
        l = %Lattice{},
        source_host,
        pk,
        link_name,
        contract_id,
        instance_id,
        spec,
        stamp,
        claims
      ) do
    provider =
      Map.get(l.providers, {pk, link_name}, %Provider{
        id: pk,
        name: Map.get(claims, "name", "unavailable"),
        issuer: Map.get(claims, "issuer", ""),
        contract_id: contract_id,
        tags: Map.get(claims, "tags", []),
        link_name: link_name,
        instances: []
      })

    instance = %Instance{
      id: instance_id,
      host_id: source_host,
      spec_id: spec,
      version: Map.get(claims, "version", ""),
      revision: Map.get(claims, "revision", 0)
    }

    provider =
      if provider.instances |> Enum.find(fn i -> i.id == instance_id end) == nil do
        %{provider | instances: [instance | provider.instances]}
      else
        provider
      end

    %Lattice{
      l
      | providers: Map.put(l.providers, {pk, link_name}, provider),
        instance_tracking:
          Map.put(l.instance_tracking, instance.id, timestamp_from_iso8601(stamp))
    }
  end

  def remove_provider_instance(l, _source_host, pk, link_name, instance_id, _spec) do
    provider = l.providers[{pk, link_name}]

    if provider != nil do
      provider = %Provider{
        provider
        | instances: provider.instances |> Enum.reject(fn i -> i.id == instance_id end)
      }

      %Lattice{
        l
        | providers: Map.put(l.providers, {pk, link_name}, provider),
          instance_tracking: l.instance_tracking |> Map.delete(instance_id)
      }
      |> strip_instanceless_entities()
    else
      l
    end
  end

  def remove_host(l = %Lattice{}, source_host) do
    # NOTE: the instance_tracking map will purge unseen instances
    # during the decay event processing.

    l = %Lattice{
      l
      | hosts: Map.delete(l.hosts, source_host),
        actors:
          l.actors
          |> Enum.map(fn {k, v} ->
            {k,
             %Actor{
               v
               | instances: v.instances |> Enum.reject(fn i -> i.host_id == source_host end)
             }}
          end)
          |> Enum.into(%{}),
        providers:
          l.providers
          |> Enum.map(fn {k, v} ->
            {k,
             %Provider{
               v
               | instances: v.instances |> Enum.reject(fn i -> i.host_id == source_host end)
             }}
          end)
          |> Enum.into(%{})
    }

    l |> strip_instanceless_entities()
  end

  def strip_instanceless_entities(l = %Lattice{}) do
    %Lattice{
      l
      | actors: l.actors |> Enum.reject(fn {_k, v} -> v.instances == [] end) |> Enum.into(%{}),
        providers:
          l.providers |> Enum.reject(fn {_k, v} -> v.instances == [] end) |> Enum.into(%{})
    }
  end

  def record_heartbeat(l = %Lattice{}, source_host, stamp, data) do
    labels = Map.get(data, "labels", %{})
    friendly_name = Map.get(data, "friendly_name", "")
    l = record_host(l, source_host, labels, stamp, friendly_name)

    l =
      List.foldl(Map.get(data, "actors", []), l, fn x, acc ->
        # TODO - once the host can emit annotations we can pull the spec
        put_actor_instance(acc, source_host, x["public_key"], x["instance_id"], "", stamp, %{})
      end)

    l =
      List.foldl(Map.get(data, "providers", []), l, fn x, acc ->
        # TODO - once the host emits annotations we can pull the spec
        put_provider_instance(
          acc,
          source_host,
          x["public_key"],
          x["link_name"],
          x["contract_id"],
          x["instance_id"],
          "",
          stamp,
          %{}
        )
      end)

    l
  end

  def record_host(l = %Lattice{}, source_host, labels, stamp, friendly_name \\ "") do
    host =
      Map.get(l.hosts, source_host, %Host{
        id: source_host,
        labels: labels,
        first_seen: timestamp_from_iso8601(stamp),
        friendly_name: friendly_name
      })

    # Every time we see a host, we set the last seen stamp
    # and bump it to healthy (TODO: support aggregate status based on
    # host contents)
    host =
      Map.merge(
        host,
        %{
          last_seen: timestamp_from_iso8601(stamp),
          status: :healthy
        }
      )

    %Lattice{l | hosts: Map.put(l.hosts, source_host, host)}
  end

  def put_linkdef(l = %Lattice{}, actor_id, link_name, provider_id, contract_id, values) do
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

  def del_linkdef(l = %Lattice{}, actor_id, link_name, provider_id) do
    %Lattice{
      l
      | linkdefs:
          Enum.reject(l.linkdefs, fn link ->
            link.actor_id == actor_id && link.link_name == link_name &&
              link.provider_id == provider_id
          end)
    }
  end

  def remove_actor_instance(l = %Lattice{}, _host_id, pk, instance_id, _spec) do
    actor = l.actors[pk]

    if actor != nil do
      actor = %Actor{
        actor
        | instances: actor.instances |> Enum.reject(fn i -> i.id == instance_id end)
      }

      %Lattice{
        l
        | actors: Map.put(l.actors, pk, actor),
          instance_tracking: l.instance_tracking |> Map.delete(instance_id)
      }
      |> strip_instanceless_entities()
    else
      l
    end
  end

  @spec timestamp_from_iso8601(binary) :: DateTime.t()
  def timestamp_from_iso8601(stamp) when is_binary(stamp) do
    case DateTime.from_iso8601(stamp) do
      {:ok, datetime, 0} -> datetime
      _ -> DateTime.utc_now()
    end
  end
end
