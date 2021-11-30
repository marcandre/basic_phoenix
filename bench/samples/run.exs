defmodule B do
  @string_len 60
  @string String.duplicate("x", @string_len)
  @average_keys true

  def run do
    tag = erlang_branch()
    IO.puts "Running for #{tag}"

    # Bypass mysterious optimization/rewriting
    maps = :maps

    Benchee.run(
      %{
        # "maps:put/3 (beam/elixir optimization?)": fn {keys, values} ->
        #   for key <- keys, do: :maps.put(key, :some_other_value, values)
        # end,
        "maps:put/3 (optimized)": fn {keys, values} ->
          for key <- keys, do: maps.putx(key, :some_other_value, values)
        end,
        "maps:put/3 (current)": fn {keys, values} ->
          for key <- keys, do: maps.put(key, :some_other_value, values)
        end,
      },
      inputs: inputs(),
      time: 1,
      #save: [path: "save.benchee", tag: tag],
      # after_each: fn _ -> :erlang.garbage_collect() end,
      #load: "save.benchee",
      warmup: 0.1
    )
  end

  defp inputs do
    for n <- [
      5,
      31,
    ],
        {key_lookup, keys} <- try_keys(n),
        {type, factory} <- factories() do
      {
        "map with #{n} #{type} keys (#{key_lookup})",
        {
          keys |> Enum.map(&factory.(&1)),
          Map.new(2..2*n//2, &{factory.(&1), :some_value})
        }
      }
    end
    |> Map.new()
  end

  defp factories do
    %{
      "binary (#{@string_len} chars)": &@string <> format_key(&1),
      # integer: & &1,
      atom: &String.to_atom("x#{format_key(&1)}"),
    }
  end

  if @average_keys do
    defp try_keys(n), do: [average_hit: 2..2*n//2, average_miss: 1..2*n+1//2]
  else
    defp try_specific_keys(n) when n < 8, do: [hit_halfway: n, miss_last: 666]
    defp try_specific_keys(n), do: [hit_first: 2, hit_halfway: n, hit_last: 2*n, miss_first: 0, miss_halfway: n+1, miss_last: 666]
    defp try_keys(n) do
      try_specific_keys(n)
      |> Enum.map(fn {name, value} -> {name, [value]} end)
    end
  end

  defp format_key(k), do: k |> to_string |> String.pad_leading(3)

  defp erlang_branch do
    erl = :erlang.system_info(:system_version) |> to_string
    with [_, hash] <- Regex.run(~r/\[source-(\w+)\]/, erl) do
      with {branch, 0} <- System.cmd("git", ["name-rev", "--name-only", hash], cd: Path.expand("~/otp")) do
        "#{String.trim(branch)} (#{hash})"
      else
        _ -> hash
      end
    else
      _ -> "OTP #{:erlang.system_info(:otp_release)}"
    end
  end
end

B.run()
