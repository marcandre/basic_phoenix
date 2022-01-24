defmodule CassetteJsonVcr do
  def __using__ do
    quote do
      defdelegate [
                    load(cassette, path),
                    save(cassette)
                  ],
                  to: CassetteVcr
    end
  end

  ### I/O

  @spec load(Checkpoint.cassette(), path :: binary) :: Checkpoint.cassette()
  def load(cassette, path) do
    %{cassette | path: path}
    |> decode_json(path |> read)
  end

  @spec save(Checkpoint.cassette()) :: Checkpoint.cassette()
  def save(%{path: nil} = cassette), do: cassette

  def save(cassette) do
    content = cassette |> encode_json

    cassette.path |> Path.dirname() |> File.mkdir_p!()

    File.write!(cassette.path, content)

    cassette
  end

  ### I/O Utilities

  defp sorted_deltas(cassette) do
    cassette.deltas
    |> Enum.sort_by(fn {key, _delta} -> cassette |> ancestry(key) |> Enum.reverse() end)
  end

  # Returns [checkpoint, parent, grand_parent, ...]
  defp ancestry(_cassette, nil), do: []

  defp ancestry(cassette, checkpoint) do
    [checkpoint | ancestry(cassette, cassette.deltas[checkpoint][:_parent])]
  end

  defp read(path) do
    case File.read(path) do
      {:ok, content} -> content
      _ -> "{}"
    end
  end

  defp decode_json(cassette, content) do
    deltas =
      content
      |> Jason.decode!(keys: :atoms)
      |> Enum.into(%{})
      |> transform_values(&parent_to_atom/1)

    %{cassette | deltas: deltas}
  end

  @spec encode_json(Cassette.t()) :: binary()
  def encode_json(cassette) do
    cassette
    |> sorted_deltas
    |> Jason.OrderedObject.new()
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end

  defp parent_to_atom(%{_parent: parent} = delta) when is_binary(parent) do
    %{delta | _parent: parent |> String.to_atom()}
  end

  defp parent_to_atom(delta), do: delta

  @doc """
  Transforms the keys of a map using a function
  """
  @spec transform_values(Enum.t(), (any -> any)) :: map
  def transform_values(source, transform) do
    source
    |> Map.map(fn {_key, value} -> transform.(value) end)
  end
end
