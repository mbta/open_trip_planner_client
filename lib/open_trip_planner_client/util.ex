defmodule OpenTripPlannerClient.Util do
  @moduledoc false

  @spec to_local_time(integer() | Timex.Types.valid_datetime()) :: DateTime.t()
  def to_local_time(datetime) when is_integer(datetime) do
    datetime
    |> Timex.from_unix(:milliseconds)
    |> to_local_time()
  end

  def to_local_time(datetime) do
    Timex.to_datetime(
      datetime,
      Application.fetch_env!(:open_trip_planner_client, :timezone)
    )
  end

  @spec local_now :: DateTime.t()
  def local_now do
    Application.fetch_env!(:open_trip_planner_client, :timezone)
    |> Timex.now()
  end
end
