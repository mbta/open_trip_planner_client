defmodule OpenTripPlannerClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :open_trip_planner_client,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]],
      test_coverage: [tool: LcovEx]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:absinthe_client, "~> 0.1.0"},
      {:bypass, "~> 2.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:jason, "~> 1.2"},
      {:lcov_ex, "~> 0.3", only: [:test], runtime: false},
      {:req, "~> 0.3"},
      {:timex, "~> 3.7"}
    ]
  end
end
