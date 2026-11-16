defmodule OpenTripPlannerClient.Util do
  @moduledoc false

  @spec to_local_time(integer() | DateTime.t()) :: DateTime.t()
  def to_local_time(datetime) when is_integer(datetime) do
    datetime
    |> DateTime.from_unix!(:millisecond)
    |> to_local_time()
  end

  def to_local_time(datetime) do
    DateTime.shift_zone!(
      datetime,
      Application.fetch_env!(:open_trip_planner_client, :timezone)
    )
  end

  @spec local_now :: DateTime.t()
  def local_now do
    Application.fetch_env!(:open_trip_planner_client, :timezone)
    |> DateTime.now!()
  end
end
