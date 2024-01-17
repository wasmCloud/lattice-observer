defmodule LatticeObserver.Observed.EventProcessor do
  alias LatticeObserver.Observed.{Lattice, Provider, Host, Actor, Instance, LinkDefinition}

  defp get_claim(_l = %Lattice{claims: claims}, field, pk, default \\ "") do
    one_claim = Map.get(claims, pk, %{})
    Map.get(one_claim, field, default)
  end

  defp safesplit_caps(""), do: []
  defp safesplit_caps(nil), do: []
  defp safesplit_caps(list) when is_list(list), do: list

  defp safesplit_caps(str) when is_binary(str) do
    str |> String.split(",") |> Enum.map(fn s -> String.trim(s) end) |> Enum.into([])
  end

  defp safesplit_tags(nil), do: ""
  defp safesplit_tags(list) when is_list(list), do: list |> Enum.join(",")
  defp safesplit_tags(str) when is_binary(str), do: str
  defp safesplit_tags(_), do: ""

  defp merge_provider(provider, l, claims) do
    name =
      case Map.get(claims, "name", "unavailable") do
        "unavailable" -> get_claim(l, :name, provider.id, "unavailable")
        name -> name
      end

    %Provider{
      provider
      | name: name,
        issuer: Map.get(claims, "issuer", get_claim(l, :iss, provider.id)),
        tags:
          Map.get(
            claims,
            "tags",
            Map.get(claims, "tags", get_claim(l, :tags, provider.id) |> safesplit_tags())
          )
    }
  end

  defp merge_actor(actor, l, claims) do
    name =
      case Map.get(claims, "name", "unavailable") do
        "unavailable" -> get_claim(l, :name, actor.id, "unavailable")
        name -> name
      end

    %Actor{
      actor
      | name: name,
        capabilities:
          Map.get(
            claims,
            "caps",
            get_claim(l, :caps, actor.id) |> safesplit_caps()
          ),
        issuer: Map.get(claims, "issuer", get_claim(l, :iss, actor.id)),
        tags: Map.get(claims, "tags", get_claim(l, :tags, actor.id) |> safesplit_tags()),
        call_alias: Map.get(claims, "call_alias", get_claim(l, :call_alias, actor.id))
    }
  end

  # Helper function to set the actor instances when an actor is scaled
  def set_actor_instances(l = %Lattice{}, host_id, pk, annotations, claims, scale)
      when is_binary(pk) and is_map(annotations) and is_integer(scale) do
    actor = Map.get(l.actors, pk, Actor.new(pk, "unavailable"))
    actor = merge_actor(actor, l, claims)
    # Reset instances
    actor = %Actor{actor | instances: []}

    # Create `scale` instances to add to the actor
    actor =
      1..scale
      |> Enum.reduce(actor, fn _i, acc ->
        instance = %Instance{
          id: "N/A",
          host_id: host_id,
          annotations: annotations,
          version: Map.get(claims, "version", get_claim(l, :version, pk)),
          revision: Map.get(claims, "revision", get_claim(l, :rev, pk, 0))
        }

        %Actor{acc | instances: [instance | acc.instances]}
      end)

    %Lattice{
      l
      | actors: Map.put(l.actors, pk, actor)
    }
  end

  # Helper function to remove all instances of an actor when it's scaled to zero
  def remove_actor(l = %Lattice{}, pk) when is_binary(pk) do
    %Lattice{
      l
      | actors: Map.delete(l.actors, pk)
    }
  end

  def put_actor_instance(l = %Lattice{}, host_id, pk, instance_id, annotations, _stamp, claims)
      when is_binary(pk) and is_binary(instance_id) and is_map(annotations) do
    actor = Map.get(l.actors, pk, Actor.new(pk, "unavailable"))
    actor = merge_actor(actor, l, claims)

    instance = %Instance{
      id: instance_id,
      host_id: host_id,
      annotations: annotations,
      version: Map.get(claims, "version", get_claim(l, :version, pk)),
      revision: Map.get(claims, "revision", get_claim(l, :rev, pk, 0))
    }

    actor = %Actor{actor | instances: [instance | actor.instances]}

    %Lattice{
      l
      | actors: Map.put(l.actors, pk, actor)
    }
  end

  def put_provider_instance(
        l = %Lattice{},
        source_host,
        pk,
        link_name,
        contract_id,
        instance_id,
        annotations,
        stamp,
        claims
      ) do
    provider =
      Map.get(l.providers, {pk, link_name}, Provider.new(pk, link_name, contract_id, [], []))

    provider = merge_provider(provider, l, claims)

    instance = %Instance{
      id: instance_id,
      host_id: source_host,
      annotations: annotations,
      version: Map.get(claims, "version", get_claim(l, :version, pk)),
      # NOTE - wasmCloud Host does not yet emit provider rev
      revision: Map.get(claims, "revision", get_claim(l, :rev, pk, "0") |> parse_revision())
    }

    # Remove old provider instance for this host and link name
    provider = %Provider{
      provider
      | instances:
          provider.instances
          |> Enum.reject(fn i -> i.host_id == source_host end)
    }

    # Add this instance back to the list
    provider = %Provider{provider | instances: [instance | provider.instances]}

    %Lattice{
      l
      | providers: Map.put(l.providers, {pk, link_name}, provider),
        instance_tracking:
          Map.put(l.instance_tracking, instance.id, timestamp_from_iso8601(stamp))
    }
  end

  def remove_provider_instance(l, source_host, pk, link_name, _spec) do
    provider = l.providers[{pk, link_name}]

    # only one provider+link name can exist per host, so this is guaranteed to
    # remove that provider since the key is already pk+link.
    if provider != nil do
      provider = %Provider{
        provider
        | instances: provider.instances |> Enum.reject(fn i -> i.host_id == source_host end)
      }

      %Lattice{
        l
        | providers: Map.put(l.providers, {pk, link_name}, provider)
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
    uptime_seconds = Map.get(data, "uptime_seconds", 0)
    version = Map.get(data, "version", "v0.0.0")

    # Heartbeats are now considered authoritative, so the previously stored
    # actor and provider list are wiped prior to recording the heartbeat, but the
    # host (and its "first seen" time) are not.
    l =
      %Lattice{
        l
        | actors:
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
      |> strip_instanceless_entities()

    l = record_host(l, source_host, labels, stamp, friendly_name, uptime_seconds, version)

    # new heartbeat has a list for the actors field with more information
    l =
      if is_list(Map.get(data, "actors", %{})) do
        put_v82_instances(l, source_host, stamp, data)
      else
        actors_expanded =
          Enum.flat_map(Map.get(data, "actors", %{}), fn {public_key, count} ->
            Enum.map(1..count, fn _ -> {public_key, %{}} end)
          end)

        l =
          List.foldl(actors_expanded, l, fn {public_key, annotations}, acc ->
            put_actor_instance(
              acc,
              source_host,
              public_key,
              "n/a",
              annotations,
              stamp,
              %{}
            )
          end)

        List.foldl(Map.get(data, "providers", []), l, fn x, acc ->
          put_provider_instance(
            acc,
            source_host,
            x["public_key"],
            x["link_name"],
            Map.get(x, "contract_id", "n/a"),
            "n/a",
            Map.get(x, "annotations", %{}),
            stamp,
            %{}
          )
        end)
      end

    l
  end

  defp put_v82_instances(l = %Lattice{}, source_host, stamp, data) do
    l =
      List.foldl(Map.get(data, "actors", []), l, fn x, all_actors ->
        id = x["id"]

        # Iterate over the instances and, using the annotations and scale, create
        # a list of instances to add to the actor.
        x["instances"]
        |> Enum.reduce(all_actors, fn instance, actors ->
          set_actor_instances(
            actors,
            source_host,
            id,
            Map.get(instance, "annotations", %{}),
            %{},
            Map.get(instance, "max_instances", 1)
          )
        end)
      end)

    List.foldl(Map.get(data, "providers", []), l, fn x, acc ->
      put_provider_instance(
        acc,
        source_host,
        x["id"],
        x["link_name"],
        x["contract_id"],
        Map.get(x, "instance_id", "n/a"),
        Map.get(x, "annotations", %{}),
        stamp,
        %{}
      )
    end)
  end

  def record_host(
        l = %Lattice{},
        source_host,
        labels,
        stamp,
        friendly_name,
        uptime_seconds,
        version
      ) do
    host =
      Map.get(l.hosts, source_host, %Host{
        id: source_host,
        labels: labels,
        first_seen: timestamp_from_iso8601(stamp),
        friendly_name: friendly_name,
        uptime_seconds: uptime_seconds,
        version: version
      })

    # Every time we see a host, we set the last seen stamp
    # and bump it to healthy (TODO: support aggregate status based on
    # host contents)
    host =
      Map.merge(
        host,
        %{
          last_seen: timestamp_from_iso8601(stamp),
          uptime_seconds: uptime_seconds,
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

  def remove_actor_instance(l = %Lattice{}, host_id, pk, _spec) do
    actor = l.actors[pk]

    if actor != nil do
      # Since there's no longer any unique distinction between actor instances on
      # the host, we can simply remove any one we like
      instances_on_host = Enum.filter(actor.instances, fn i -> i.host_id == host_id end)

      actor = %Actor{
        actor
        | instances: Enum.drop(instances_on_host, 1)
      }

      %Lattice{
        l
        | actors: Map.put(l.actors, pk, actor)
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

  defp parse_revision(rev) when is_number(rev), do: rev
  defp parse_revision(rev) when is_binary(rev), do: rev |> String.to_integer()
  defp parse_revision(_), do: 0
end
