defmodule Checkpoints.Ecto do

### Utility functions for Changeset

def record_to_params(record, schema) do
  [
    Map.take(record, schema.fields),
    Map.map(schema.embeds, fn {embed_name, embed_schema} ->
      record_to_params(Map.get(record, embed_name), embed_schema)
    end)),
    Map.map(schema.one_assocs, fn {assoc_name, assoc_schema} ->
      record_to_params(Map.get(record, assoc_name), assoc_schema)
    end),
    Map.map(schema.many_assocs, fn {assoc_name, assoc_schema} ->
      Map.get(record, assoc_name)
      |> Enum.map(&record_to_params(&1, assoc_schema))
    end),
  ] |> Enum.reduce(&Map.merge/2)
end

# Recursively transforms changesets to list of changes.
def changeset_to_delta(%Changeset{} = changeset),
  do: changeset.changes |> Utilities.Map.transform_values(&changeset_to_delta/1)

def changeset_to_delta(changesets) when is_list(changesets),
  do: changesets |> Enum.map(&changeset_to_delta/1)

def changeset_to_delta(changes), do: changes

def changeset_fn(schema, options \\ []) do
  fn record, params ->
    changeset =
      record
      |> Changeset.cast(params, schema.fields, empty_values: [])

    changeset =
      schema.embeds
      |> Enum.reduce(changeset, fn {embed_name, embed_schema}, changeset ->
        changeset |> Changeset.cast_embed(embed_name, with: embed_schema.changeset_fn)
      end)

    Map.merge(schema.one_assocs, schema.many_assocs)
    |> Enum.reduce(changeset, fn {assoc_name, assoc_schema}, changeset ->
      changeset |> Changeset.cast_assoc(assoc_name, with: assoc_schema.changeset_fn)
    end)
  end
end

# TODO: Segregate
def record_to_changeset(cassette, record) do
  # FIXME: use option if given
  params = record |> record_to_params
  cassette.changeset_fn.(cassette.initial_record, params)
end

defp to_embed_name_fn(embed, base_schema, options \\ [])

defp to_embed_name_fn({embed_name, options}, base_schema, []),
  do: to_embed_name_fn(embed_name, base_schema, options)

defp to_embed_name_fn(embed_name, _base_schema, fun) when is_function(fun),
  do: {embed_name, fun}

defp to_embed_name_fn(embed_name, base_schema, options) do
  embed_schema = base_schema.__schema__(:embed, embed_name).related
  {embed_name, changeset_fn(embed_schema, options)}
end

defp to_assoc_name_fn(assoc, base_schema, options \\ [])

defp to_assoc_name_fn({assoc_name, options}, base_schema, []),
  do: to_assoc_name_fn(assoc_name, base_schema, options)

defp to_assoc_name_fn(assoc_name, _base_schema, fun) when is_function(fun),
  do: {assoc_name, fun}

defp to_assoc_name_fn(assoc_name, base_schema, options) do
  assoc_schema = base_schema.__schema__(:association, assoc_name).related
  {assoc_name, changeset_fn(assoc_schema, options)}
end

defp changeset_fields(schema, options) do
  schema.__schema__(:fields)
  # Remove primary key and all belongs_to assocs:
  |> Enum.filter(&(schema.__schema__(:type, &1) != :id))
  |> Kernel.--(schema.__schema__(:embeds))
  |> Kernel.--([:inserted_at, :updated_at])
  |> Kernel.--(options[:exclude_fields] |> List.wrap())
  |> Kernel.++(options[:include_fields] |> List.wrap())
end

def params_delta(from_params, to_params) when is_map(from_params) and is_map(to_params) do
  missing = (Map.keys(from_params) -- Map.keys(to_params)) |> Enum.map(&{&1, nil})

  to_params
  |> Enum.filter(fn {key, value} -> from_params[key] != value end)
  |> Kernel.++(missing)
  |> Map.new(fn {key, value} -> {key, params_delta(from_params[key], value)} end)
end

def params_delta(from_params, to_params) when is_list(from_params) and is_list(to_params) do
  params_delta_list([], from_params, to_params)
  |> Enum.reverse()
end

def params_delta(_from_params, to_params), do: to_params

defp params_delta_list(into, _, []), do: into

defp params_delta_list(into, [from_hd | from_tl], [to_hd | to_tl]) do
  [params_delta(from_hd, to_hd) | into]
  |> params_delta_list(from_tl, to_tl)
end

defp params_delta_list(into, [], [to_hd | to_tl]) do
  [to_hd | into]
  |> params_delta_list([], to_tl)
end

defp empty_struct(schema, options) do
  empty = struct(schema)
  assocs = options[:assocs] || []
  # || schema.__schema__(:associations)

  assocs
  |> Enum.reduce(empty, fn assoc, empty ->
    case schema.__schema__(:association, assoc) do
      # %Ecto.Association.BelongsTo{} -> [TODO]

      %Ecto.Association.Has{cardinality: :many} ->
        %{empty | assoc => []}
    end
  end)

  @type schema :: %{
          changeset_fn: (any, any -> any),
          fields: [atom],
          embeds: %{atom => schema},
          has_many_assocs: %{atom => schema},
          has_one_assocs: %{atom => schema},
          options: %{atom => Keyword.t()}
        }


  def default(:fields, ecto_schema) do
    ecto_schema.__schema__(:fields)
    # Remove primary key and all belongs_to assocs:
    |> Enum.filter(&(ecto_schema.__schema__(:type, &1) != :id))
    |> Kernel.--(ecto_schema.__schema__(:embeds))
    |> Kernel.--([:inserted_at, :updated_at])
  end

  def default(:embeds, ecto_schema) do
    ecto_schema.__schema__(:embeds)
  end

  def default(:many_assocs, ecto_schema, exclude_foreign_key),
  do: default_associations(:many, ecto_schema, exclude_foreign_key)

  def default(:one_assocs, ecto_schema, exclude_foreign_key),
  do: default_associations(:one, ecto_schema, exclude_foreign_key)

  defp default_associations(cardinality, ecto_schema, exclude_foreign_key) do
    ecto_schema.__schema__(:associations),
    |> Enum.filter(fn assoc ->
      case ecto_schema.__schema__(:association, assoc) do
        %{
          cardinality: ^cardinality,
          foreign_key: key,
        } where key != exclude_foreign_key -> info -> true
        _ -> false
        end
      end)
  end

  defp to_name_option(what, ecto_schema, all_options) do
    list = all_options[what] || default(what, ecto_schema)

    list |> Enum.map(fn
      {name, option} when is_list(option) -> {name, option},
      {name, changeset_fn} when is_function(changeset_fn) -> {name, [changeset_fn: changeset_fn]},
      name -> {name, all_options[name] || []}
    end)
  end

  defp to_name_schema_kw(what, ecto_schema, all_options, exclude_foreign_key) do
    to_name_option(what, ecto_schema, all_options, exclude_foreign_key)
    |> Enum.map(fn {name, options} ->
      {name, to_schema(ecto_schema, options, exclude_reverse(what, ecto_schema, name))
    end)
  end

  defp exclude_reverse(:one_assocs, ecto_schema, name) do
    ecto_schema.__schema__(:association, name)
    {:many_assocs, :some_foreign_key}
    # [wip]
  end

  def to_schema(ecto_schema, options, exclude_foreign_key_kw \\ []) do
    %Schema{
      fields: to_name_schema_kw(:fields, ecto_schema, all_options),
      embeds: to_name_schema_kw(:embeds, ecto_schema, all_options),
      one_assocs: to_name_schema_kw(:one_assocs, ecto_schema, all_options, exclude_foreign_key_kw[:one_assocs]),
      many_assocs: to_name_schema_kw(:one_assocs, ecto_schema, all_options, exclude_foreign_key_kw[:many_assocs]),
    }
  end
end

assocs: [:foo, bar: %{}]
