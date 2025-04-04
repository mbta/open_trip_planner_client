defmodule Mix.Tasks.UpdateFixture do
  @moduledoc "Run: `mix update_fixture` to request new data."
  use Mix.Task

  alias OpenTripPlannerClient.PlanParams

  @shortdoc "Populate the alewife_to_franklin_park_zoo fixture with new data"
  @spec run(command_line_args :: [binary]) :: any()
  def run(_) do
    Mix.Task.run("app.start")

    {:ok, query_result} =
      %{
        fromPlace: "::mbta-ma-us:place-alfcl",
        toPlace: "Franklin Park Zoo::42.305067,-71.090434"
      }
      |> PlanParams.new()
      |> OpenTripPlannerClient.send_request()

    encoded = Jason.encode!(%{data: query_result}, pretty: true)

    File.write("test/fixture/alewife_to_franklin_park_zoo.json", encoded)
  end
end
