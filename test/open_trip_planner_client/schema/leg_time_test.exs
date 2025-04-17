defmodule LegTimeTest do
  use ExUnit.Case, async: true

  import OpenTripPlannerClient.Test.Support.Factory

  alias OpenTripPlannerClient.Schema.LegTime

  describe "time/1" do
    test "outputs estimated time if available" do
      estimated = build(:leg_time_estimated)
      leg_time = build(:leg_time, estimated: estimated)

      assert LegTime.time(leg_time) == estimated.time
      refute LegTime.time(leg_time) == leg_time.scheduled_time
    end

    test "otherwise outputs scheduled time" do
      leg_time = build(:leg_time, estimated: nil)

      assert LegTime.time(leg_time) == leg_time.scheduled_time
    end
  end
end
