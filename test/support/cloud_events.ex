defmodule TestSupport.CloudEvents do
  @appspec "wasmcloud.dev/appspec"

  @spec actor_started(any, any, any, any, any) :: %{
          :__struct__ =>
            Cloudevents.Format.V_0_1.Event
            | Cloudevents.Format.V_0_2.Event
            | Cloudevents.Format.V_1_0.Event,
          :data => any,
          :extensions => %{optional(binary) => any},
          :source => binary,
          optional(:cloudEventsVersion) => <<_::24>>,
          optional(:contentType) => nil | binary,
          optional(:contenttype) => nil | binary,
          optional(:datacontenttype) => nil | binary,
          optional(:dataschema) => nil | binary,
          optional(:eventID) => binary,
          optional(:eventTime) => nil | binary,
          optional(:eventType) => binary,
          optional(:id) => binary,
          optional(:schemaURL) => nil | binary,
          optional(:schemaurl) => nil | binary,
          optional(:specversion) => <<_::24>>,
          optional(:subject) => nil | binary,
          optional(:time) => nil | binary,
          optional(:type) => binary
        }
  def actor_started(pk, instance_id, spec, host, name \\ "Test Actor") do
    %{
      "public_key" => pk,
      "instance_id" => instance_id,
      "annotations" => %{@appspec => spec},
      "claims" => %{
        "name" => name,
        "caps" => ["test", "test2"],
        "version" => "1.0",
        "revision" => 0,
        "tags" => [],
        "issuer" => "ATESTxxx"
      }
    }
    |> LatticeObserver.CloudEvent.new("actor_started", host)
  end

  def actor_stopped(pk, instance_id, spec, host) do
    %{"public_key" => pk, "instance_id" => instance_id, "annotations" => %{@appspec => spec}}
    |> LatticeObserver.CloudEvent.new("actor_stopped", host)
  end

  def host_started(host, labels, friendly_name \\ "default-runner-1") do
    %{
      "labels" => labels,
      "friendly_name" => friendly_name
    }
    |> LatticeObserver.CloudEvent.new("host_started", host)
  end

  def host_stopped(host) do
    %{} |> LatticeObserver.CloudEvent.new("host_stopped", host)
  end

  def decay_tick(time) do
    stamp = time |> DateTime.to_iso8601()

    %{
      specversion: "1.0",
      time: stamp,
      type: "com.wasmcloud.synthetic.decay_ticked",
      source: "none",
      datacontenttype: "application/json",
      id: UUID.uuid4(),
      data: nil
    }
    |> Cloudevents.from_map!()
  end

  def provider_started(pk, contract_id, link_name, instance_id, spec, host) do
    %{
      "public_key" => pk,
      "instance_id" => instance_id,
      "link_name" => link_name,
      "contract_id" => contract_id,
      "annotations" => %{@appspec => spec},
      "claims" => %{
        "name" => "test provider",
        "version" => "1.0",
        "revision" => 2,
        "issuer" => "ATESTxxx",
        "tags" => ["a", "b"]
      }
    }
    |> LatticeObserver.CloudEvent.new("provider_started", host)
  end

  def provider_stopped(pk, contract_id, link_name, instance_id, spec, host) do
    %{
      "public_key" => pk,
      "instance_id" => instance_id,
      "link_name" => link_name,
      "contract_id" => contract_id,
      "annotations" => %{@appspec => spec}
    }
    |> LatticeObserver.CloudEvent.new("provider_stopped", host)
  end

  def host_heartbeat(host, labels, actors \\ [], providers \\ []) do
    %{
      "actors" => actors,
      "providers" => providers,
      "labels" => labels
    }
    |> LatticeObserver.CloudEvent.new("host_heartbeat", host)
  end

  def linkdef_put(actor_id, provider_id, link_name, contract_id, values, host) do
    %{
      "actor_id" => actor_id,
      "provider_id" => provider_id,
      "link_name" => link_name,
      "contract_id" => contract_id,
      "values" => values
    }
    |> LatticeObserver.CloudEvent.new("linkdef_set", host)
  end

  def linkdef_del(actor_id, provider_id, link_name, contract_id, host) do
    %{
      "actor_id" => actor_id,
      "provider_id" => provider_id,
      "link_name" => link_name,
      "contract_id" => contract_id
    }
    |> LatticeObserver.CloudEvent.new("linkdef_deleted", host)
  end

  def invocation_succeeded(from = %{}, to = %{}, bytes, operation, host) do
    %{
      "source" => from,
      "dest" => to,
      "operation" => operation,
      "bytes" => bytes
    }
    |> LatticeObserver.CloudEvent.new("invocation_succeeded", host)
  end

  def invocation_failed(from = %{}, to = %{}, bytes, operation, host) do
    %{
      "source" => from,
      "dest" => to,
      "operation" => operation,
      "bytes" => bytes
    }
    |> LatticeObserver.CloudEvent.new("invocation_failed", host)
  end
end
