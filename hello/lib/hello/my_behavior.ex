defmodule MyBehaviour do
  @callback start_value() :: any

  def new(cassette) do
    %{cassette | deltas: cassette.start_value()}
  end

  def decode(cassette, value) do
    %{cassette | deltas: value}
  end
end

defmodule ExtraBehavior do
  @behaviour MyBehaviour

  @callback extra() :: any
end

defmodule MyImpl do
  @behaviour ExtraBehavior

  # def start_value, do: 42
  def extra, do: 42

  defstruct deltas: %{}
end

# defmodule ExtraBehavior do
#   @bh
# end
