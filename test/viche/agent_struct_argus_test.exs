defmodule Viche.AgentStructArgusTest do
  use ExUnit.Case, async: true
  alias Viche.Agents

  test "Argus: type invariant — Agent capabilities, name, and description must be strings" do
    invalid_input = %{
      capabilities: [123, %{}],
      name: 456,
      description: []
    }

    # This test FAILS if the bug exists (i.e. the function accepts the invalid input)
    # We expect it to raise or return an error, not {:ok, agent}
    assert {:error, _} = Agents.register_agent(invalid_input)
  end
end
