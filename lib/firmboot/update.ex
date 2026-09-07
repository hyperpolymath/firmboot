defmodule Firmboot.Update do
  @moduledoc """
  An update in the finite experiment model. Costs are simulated clock units.

  Faults are controlled test injections, not arbitrary untrusted code. Neither
  this struct nor the model is a compiler, sandbox, or proof-certificate checker.
  """
  @enforce_keys [:id, :target]
  defstruct [:id, :target, prepare_ticks: 2, prepare_cost: 1, commit_cost: 1, fault: :none]
end
