defmodule LatticeObserver.MixProject do
  use Mix.Project

  def project do
    [
      app: :lattice_observer,
      version: "0.3.0",
      elixir: "~> 1.12",
      elixirc_paths: compiler_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {LatticeObserver.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:cloudevents, "~> 0.6.1"},
      {:uuid, "~> 1.1"},
      {:jason, "~> 1.2"}
    ]
  end

  def compiler_paths(:test), do: ["lib", "test/support"]
  def compiler_paths(_), do: ["lib"]
end
