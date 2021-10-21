defmodule LatticeObserver.MixProject do
  use Mix.Project

  def project do
    [
      app: :lattice_observer,
      version: "0.1.0",
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
      {:cloudevents, "~> 0.4.0"},
      {:uuid, "~> 1.1"},
      {:gnat, "~> 1.3"},
      {:jason, "~> 1.2"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  def compiler_paths(:test), do: ["lib", "test/support"]
  def compiler_paths(_), do: ["lib"]
end
