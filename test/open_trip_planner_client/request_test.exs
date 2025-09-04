defmodule OpenTripPlannerClient.RequestTest do
  @moduledoc false
  use ExUnit.Case, async: false

  import OpenTripPlannerClient.Request
  import OpenTripPlannerClient.Test.Support.Factory

  setup do
    bypass = Bypass.open()
    host = "http://localhost:#{bypass.port}"
    old_otp_url = Application.get_env(:open_trip_planner_client, :otp_url)

    on_exit(fn ->
      Application.put_env(:open_trip_planner_client, :otp_url, old_otp_url)
    end)

    Application.put_env(:open_trip_planner_client, :otp_url, host)

    {:ok, %{bypass: bypass}}
  end

  describe "plan_connection/1" do
    test "can apply accept-language request header", %{bypass: bypass} do
      plan_params = build(:plan_params)

      Bypass.expect_once(bypass, fn conn ->
        assert Plug.Conn.get_req_header(conn, "accept-language") == [plan_params.locale]

        Plug.Conn.send_resp(conn, :ok, "{}")
      end)

      _ = plan_connection(plan_params)
    end
  end
end
