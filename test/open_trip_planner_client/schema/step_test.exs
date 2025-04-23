defmodule StepTest do
  use ExUnit.Case, async: true

  import OpenTripPlannerClient.Test.Support.Factory

  alias OpenTripPlannerClient.Schema.Step

  describe "walk_summary/1" do
    test "shows text" do
      for relative <- Step.relative_direction(),
          absolute <- Step.absolute_direction() do
        step = build(:step, absolute_direction: absolute, relative_direction: relative)
        assert Step.walk_summary(step) |> is_binary()
      end
    end

    test "handles bogus Transfer street name" do
      step = build(:step, street_name: "Transfer", relative_direction: :DEPART)
      assert Step.walk_summary(step) == "Transfer"
    end

    test "handles other situations gracefully" do
      step = build(:step, absolute_direction: :SKYWARDS, relative_direction: :JUMP)
      assert Step.walk_summary(step) == "Go onto #{step.street_name}"
    end
  end
end
