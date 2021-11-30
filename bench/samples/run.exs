list = Enum.to_list(1..10_000)
map_fun = &to_string/1

Benchee.run(
  %{
    "map_join" => fn -> Enum.map_join(list, "/", map_fun) end,
    "map.join" => fn -> list |> Enum.map(map_fun) |> Enum.join("/") end
  },
  time: 10,
  memory_time: 2
)
