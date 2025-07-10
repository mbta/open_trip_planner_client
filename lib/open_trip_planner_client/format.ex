defmodule OpenTripPlannerClient.Format do
  @moduledoc """
  Functions for formatting localized dates/times.
  """

  alias OpenTripPlannerClient.Cldr.{DateTime, Time}
  alias Timex.{Duration, Format.Duration.Formatter}

  @doc """
  Renders a datetime as a short time, localized to the selected
  locale.

  ## Examples
  iex> ~U[2020-05-30 13:52:56Z]
  ...> |> OpenTripPlannerClient.Format.humanized_localized_time()
  "1:52 pm"
  """
  @spec humanized_localized_time(Timex.Types.valid_datetime()) :: String.t()
  def humanized_localized_time(time) do
    case Time.to_string(time, format: :short, period: :variant) do
      {:ok, formatted_time} ->
        formatted_time

      _ ->
        Timex.format!(time, "{h12}:{m} {am}")
    end
  end

  @doc """
  Renders a datetime as a short phrase depicting a date at a time, 
  localized to the selected locale.

  ## Examples
  iex> ~U[2020-05-30 13:52:56Z]
  ...> |> OpenTripPlannerClient.Format.humanized_localized_date_at_time()
  "Saturday, May 30, 2020 at 1:52 pm"
  """
  @spec humanized_localized_date_at_time(Timex.Types.valid_datetime()) :: String.t()
  def humanized_localized_date_at_time(datetime) do
    case DateTime.to_string(datetime,
           format: :full,
           time_format: :short,
           style: :at,
           period: :variant
         ) do
      {:ok, formatted_time} ->
        formatted_time

      _ ->
        Timex.format!(datetime, "{WDfull}, {Mfull} {D} at {h12}:{m} {am}")
    end
  end

  @doc """
  Renders a number in seconds as a time duration, localized to the
  selected locale.

  ## Examples
  iex> 333
  ...> |> OpenTripPlannerClient.Format.humanized_localized_duration()
  "5 minutes, 33 seconds"
  """
  @spec humanized_localized_duration(number()) :: String.t()
  def humanized_localized_duration(seconds) do
    case DateTime.Relative.to_string(seconds, format: :long) do
      {:ok, formatted_duration} ->
        formatted_duration

      _ ->
        seconds
        |> Duration.from_seconds()
        |> Formatter.format(:humanized)
    end
  end
end
