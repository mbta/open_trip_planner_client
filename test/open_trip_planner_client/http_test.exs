defmodule OpenTripPlannerClient.HttpTest do
  @moduledoc """
  Tests for OpenTripPlanner that require overriding the OTP host or making
  external requests.

  We pull these into a separate module so that the main body of tests can
  remain async: true.

  """
  use ExUnit.Case, async: false

  import OpenTripPlannerClient
  import OpenTripPlannerClient.Test.Support.Factory
  import Plug.Conn, only: [send_resp: 3]

  alias OpenTripPlannerClient.{ItineraryGroup, ItineraryTag, Plan}

  setup context do
    if context[:external] do
      :ok
    else
      bypass = Bypass.open()
      host = "http://localhost:#{bypass.port}"
      old_otp_url = Application.get_env(:open_trip_planner_client, :otp_url)
      old_level = Logger.level()

      on_exit(fn ->
        Application.put_env(:open_trip_planner_client, :otp_url, old_otp_url)
        Logger.configure(level: old_level)
      end)

      Application.put_env(:open_trip_planner_client, :otp_url, host)
      Logger.configure(level: :info)

      {:ok, %{bypass: bypass}}
    end
  end

  describe "plan/2 with fixture data" do
    @fixture File.read!("test/fixture/alewife_to_franklin_park_zoo.json")

    test "can apply tags", %{bypass: bypass} do
      Bypass.expect_once(bypass, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(:ok, @fixture)
      end)

      {:ok, itinerary_groups} =
        plan(
          build(:plan_params),
          [
            ItineraryTag.EarliestArrival,
            ItineraryTag.LeastWalking,
            ItineraryTag.ShortestTrip
          ]
        )

      assert itinerary_groups

      {untagged, tagged} =
        Enum.split_with(itinerary_groups, fn group ->
          representative_tag(group)
          |> is_nil()
        end)

      assert untagged
             |> Enum.map(&representative_tag/1)
             |> Enum.all?(&is_nil/1)

      assert Enum.map(tagged, &representative_tag/1) |> Enum.all?()
    end

    test "uses locale", %{bypass: bypass} do
      locale = "es"

      Bypass.expect_once(bypass, fn conn ->
        assert {"accept-language", locale} in conn.req_headers

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(:ok, @fixture)
      end)

      {:ok, itinerary_groups} =
        build(:plan_params, locale: locale)
        |> plan()

      group = List.first(itinerary_groups)
      assert group.alternatives_text =~ "Viaje"
    end

    defp representative_tag(group) do
      ItineraryGroup.representative_itinerary(group)
      |> Map.get(:tag)
    end
  end

  describe "plan/2 with real OTP" do
    @describetag :external

    test "can make a basic plan with OTP" do
      params = build(:plan_params)
      {:ok, plan} = plan(params)
      assert %Plan{} = plan
      refute plan.itineraries == []
    end
  end

  describe "error handling/logging" do
    @tag :capture_log
    test "HTTP errors are converted to error tuples", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        send_resp(conn, 500, "{}")
      end)

      assert {:error, _} = plan(build(:plan_params))
    end

    @tag :capture_log
    test "connection errors are converted to error tuples", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, _} = plan(build(:plan_params))
    end
  end
end
