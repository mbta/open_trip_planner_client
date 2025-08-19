defmodule Mix.Tasks.UpdateFixture do
  @shortdoc "Update the Alewife-to-Franlin-Park fixture"
  @moduledoc "Run: `mix update_fixture` to request new data."
  use Mix.Task

  alias OpenTripPlannerClient.{Parser, PlanParams, Request}

  @spec run(command_line_args :: [binary]) :: any()
  def run(_) do
    Mix.Task.run("app.start")

    params =
      PlanParams.new(%{name: "Alewife", latitude: 42.396148, longitude: -71.140698}, %{
        name: "Franklin Park Zoo",
        latitude: 42.305067,
        longitude: -71.090434
      })

    {:ok, %{body: body}} = Request.plan_connection(params)
    {:ok, query_result} = Parser.validate_body(body)

    encoded = Jason.encode!(%{"data" => Nestru.encode!(query_result)}, pretty: true)

    File.write("test/fixture/alewife_to_franklin_park_zoo.json", encoded)
  end
end
