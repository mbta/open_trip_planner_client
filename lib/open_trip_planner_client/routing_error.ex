defmodule OpenTripPlannerClient.Plan.RoutingError do
  @moduledoc """
  Description of the reason, why the planner did not return any results
  """

  use OpenTripPlannerClient.Schema

  @routing_error_codes [
    :NO_TRANSIT_CONNECTION,
    :NO_TRANSIT_CONNECTION_IN_SEARCH_WINDOW,
    :OUTSIDE_SERVICE_PERIOD,
    :OUTSIDE_BOUNDS,
    :LOCATION_NOT_FOUND,
    :NO_STOPS_IN_RANGE,
    :WALKING_BETTER_THAN_TRANSIT
  ]

  @typedoc """
  Corresponds to `RoutingErrorCode` from OTP `planConnection` query.
  Possible values as of OTPv2.7.0:

  * `NO_TRANSIT_CONNECTION`: No transit connection was found between the origin
  and destination within the operating day or the next day, not even sub-optimal
  ones.

  * `NO_TRANSIT_CONNECTION_IN_SEARCH_WINDOW`: A transit connection was found,
  but it was outside the search window. See the metadata for a token for
  retrieving the result outside the search window.

  * `OUTSIDE_SERVICE_PERIOD`: The date specified is outside the range of data
  currently loaded into the system as it is too far into the future or the past.
  The specific date range of the system is configurable by an administrator and
  also depends on the input data provided.

  * `OUTSIDE_BOUNDS`: The coordinates are outside the geographic bounds of the
  transit and street data currently loaded into the system and therefore cannot
  return any results.

  * `LOCATION_NOT_FOUND`: The specified location is not close to any streets or
  transit stops currently loaded into the system, even though it is generally
  within its bounds. This can happen when there is only transit but no street
  data coverage at the location in question.

  * `NO_STOPS_IN_RANGE`: No stops are reachable from the start or end locations
  specified. You can try searching using a different access or egress mode, for
  example cycling instead of walking, increase the walking/cycling/driving speed
  or have an administrator change the system's configuration so that stops
  further away are considered.

  * `WALKING_BETTER_THAN_TRANSIT`: Transit connections were requested and found
  but because it is easier to just walk all the way to the destination they were
  removed. If you want to still show the transit results, you need to make
  walking less desirable by increasing the walk reluctance.
  """
  @type code ::
          unquote(
            @routing_error_codes
            |> Enum.map_join(" | ", &inspect/1)
            |> Code.string_to_quoted!()
          )

  defimpl Nestru.PreDecoder do
    # credo:disable-for-next-line
    def gather_fields_for_decoding(_, _, map) do
      updated_map =
        map
        |> update_in(["code"], &OpenTripPlannerClient.Util.to_uppercase_atom/1)
        |> update_in(["input_field"], &OpenTripPlannerClient.Util.to_uppercase_atom/1)

      {:ok, updated_map}
    end
  end

  @derive [
    {Nestru.Decoder,
     hint: %{
       code: &__MODULE__.to_atom/1,
       input_field: &__MODULE__.to_atom/1
     }}
  ]
  schema do
    field(:code, code(), @nonnull_field)
    field(:description, String.t(), @nonnull_field)
    field(:input_field, :DATE_TIME | :FROM | :TO)
  end

  @spec to_atom(any()) :: {:ok, any()}
  def to_atom(term), do: {:ok, OpenTripPlannerClient.Util.to_uppercase_atom(term)}
end
