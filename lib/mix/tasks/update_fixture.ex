defmodule Mix.Tasks.UpdateFixture do
  @moduledoc "Run: `mix update_fixture` to request new data."
  use Mix.Task

  alias OpenTripPlannerClient.PlanParams

  @spec run(command_line_args :: [binary]) :: any()
  def run(_) do
    Mix.Task.run("app.start")

    params =
      PlanParams.new(
        %{name: "Alewife", latitude: 42.396148, longitude: -71.140698},
        %{
          name: "Franklin Park Zoo",
          latitude: 42.305067,
          longitude: -71.090434
        },
        num_itineraries: 20
      )

    {:ok, plan} = OpenTripPlannerClient.send_request(params)

    encoded = Jason.encode!(%{data: %{plan: plan}}, pretty: true)

    File.write("test/fixture/alewife_to_franklin_park_zoo.json", encoded)
  end
end
