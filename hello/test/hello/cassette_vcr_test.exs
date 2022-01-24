defmodule PersistableCheckpoints do
  defstruct deltas: %{}, path: nil
  @behavior Checkpoints
  use CassetteVcr
end
