defmodule OpenTripPlannerClient.ParserTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  import OpenTripPlannerClient.Parser
  import OpenTripPlannerClient.Test.Support.Factory

  describe "validate_body/1" do
    test "handles GraphQL request error" do
      assert {{:error, errors}, log} =
               with_log(fn ->
                 validate_body(%{
                   errors: [
                     %{
                       message:
                         "Validation error (UndefinedVariable@[plan]) : Undefined variable 'from'",
                       locations: [
                         %{
                           line: 3,
                           column: 16
                         }
                       ],
                       extensions: %{
                         classification: "ValidationError"
                       }
                     },
                     %{
                       message: "Validation error (UnusedVariable) : Unused variable 'fromPlace'",
                       locations: [
                         %{
                           line: 1,
                           column: 16
                         }
                       ],
                       extensions: %{
                         classification: "ValidationError"
                       }
                     }
                   ]
                 })
               end)

      assert errors == [
               %OpenTripPlannerClient.Error{
                 details: %{
                   extensions: %{classification: "ValidationError"},
                   locations: [%{line: 3, column: 16}]
                 },
                 message:
                   "Validation error (UndefinedVariable@[plan]) : Undefined variable 'from'",
                 type: :graphql_error
               },
               %OpenTripPlannerClient.Error{
                 details: %{
                   extensions: %{classification: "ValidationError"},
                   locations: [%{line: 1, column: 16}]
                 },
                 message: "Validation error (UnusedVariable) : Unused variable 'fromPlace'",
                 type: :graphql_error
               }
             ]

      assert log =~ "Validation error"
    end

    test "handles GraphQL field error" do
      {{:error, [error]}, log} =
        with_log(fn ->
          validate_body(%{
            data: %{plan: nil},
            errors: [
              %{
                message:
                  "Exception while fetching data (/plan) : The value is not in range[0.0, 1.7976931348623157E308]: -5.0",
                locations: [
                  %{
                    line: 2,
                    column: 3
                  }
                ],
                path: [
                  "plan"
                ],
                extensions: %{
                  classification: "DataFetchingException"
                }
              }
            ]
          })
        end)

      assert error == %OpenTripPlannerClient.Error{
               details: %{
                 path: ["plan"],
                 extensions: %{classification: "DataFetchingException"},
                 locations: [%{line: 2, column: 3}]
               },
               message:
                 "Exception while fetching data (/plan) : The value is not in range[0.0, 1.7976931348623157E308]: -5.0",
               type: :graphql_error
             }

      assert log =~ "Exception while fetching data"
    end

    test "handles and logs routing errors" do
      code = "PATH_NOT_FOUND"
      routing_error = build(:routing_error, code: code)

      assert {{:error, errors}, log} =
               with_log(fn ->
                 validate_body(%{
                   data: %{plan: %{routing_errors: [routing_error]}}
                 })
               end)

      assert [
               %OpenTripPlannerClient.Error{
                 details: ^routing_error,
                 message: "Something went wrong.",
                 type: :routing_error
               }
             ] = errors

      assert log =~ code
    end

    test "does not treat 'WALKING_BETTER_THAN_TRANSIT' as a fatal error" do
      assert {:ok, %OpenTripPlannerClient.Plan{}} =
               validate_body(%{
                 data: %{plan: %{routing_errors: [%{code: "WALKING_BETTER_THAN_TRANSIT"}]}}
               })
    end

    test "handles a nil plan" do
      assert {{:error, :no_plan}, _log} =
               with_log(fn ->
                 validate_body(%{
                   data: %{plan: nil}
                 })
               end)
    end

    test "handles a missing plan" do
      assert {{:error, :no_data}, _log} =
               with_log(fn ->
                 validate_body(%{
                   data: %{}
                 })
               end)
    end
  end
end
