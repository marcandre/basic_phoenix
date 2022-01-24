defmodule Bobby.CheckpointVcr do
  @type record :: any
  @type delta :: map
  @type checkpoint :: atom
  @type deltas :: %{checkpoint => delta}
  @type cassette :: struct

  @callback empty_record() :: delta
  @callback delta(parent :: record, child :: record) :: delta
  @callback apply_delta(base :: record, delta :: delta) :: record
  @callback save(cassette :: cassette) :: any

  @optional_callbacks save: 1
  @doc """
  Returns the record for the given checkpoint, or `nil` if the checkpoint has not been recorded.
  """
  def get_record(cassette, nil), do: module(cassette).empty_record()

  def get_record(cassette, checkpoint) do
    if delta = cassette.deltas[checkpoint] do
      parent_checkpoint = delta[:_parent]
      from_record = get_record!(cassette, parent_checkpoint)
      module(cassette).apply_delta(from_record, delta)
    end
  end

  defp module(cassette), do: cassette.__struct__

  @doc """
  Returns the record for the given checkpoint, or raises if the checkpoint has not been recorded.
  """
  def get_record!(cassette, checkpoint) do
    get_record(cassette, checkpoint) || raise("No record found for #{checkpoint}")
  end

  @doc """
  Returns the full delta from the `initial_record` to the given checkpoint,
  or `nil` if the checkpoint has not been recorded.
  """
  def get_delta(cassette, checkpoint) do
    record = get_record(cassette, checkpoint)
    origin_record = get_record!(cassette, nil)

    record && module(cassette).delta(origin_record, record)
  end

  @doc """
  Returns the full delta from the `initial_record` to the given checkpoint,
  or raises if the checkpoint has not been recorded.
  """
  def get_delta!(cassette, checkpoint) do
    get_delta(cassette, checkpoint) || raise("No record found for #{checkpoint}")
  end

  @doc """
  Returns the delta between the given record and the recorded checkpoint,
  or `:==` if they match.
  If the checkpoint has not been recorded, `nil` is returned.
  """
  def compare(cassette, record, checkpoint) do
    case cassette |> get_record(checkpoint) do
      nil ->
        nil

      expected_record ->
        delta = module(cassette).delta(expected_record, record)

        if delta == %{}, do: :==, else: delta
    end
  end

  @doc """
  Compares the given record to the recorded checkpoint.
  Returns `{:==, cassette}` if they match or if the checkpoint was recorded
  (in which case the cassette has been updated),
  `{:!=, delta}` if they don't match.
  In case where the parent checkpoint is different from the recorded one,
  `{:error, message}` is returned.
  """
  def compare_or_update(cassette, record, checkpoint, parent_checkpoint \\ nil) do
    case compare(cassette, record, checkpoint) do
      nil ->
        {:==, update(cassette, record, checkpoint, parent_checkpoint)}

      :== ->
        case cassette.deltas[checkpoint][:_parent] do
          ^parent_checkpoint ->
            {:==, cassette}

          actual_parent_checkpoint ->
            {:error,
             "Expected parent of checkpoint #{checkpoint} to be #{parent_checkpoint} but is is #{actual_parent_checkpoint}"}
        end

      delta ->
        {:!=, delta}
    end
  end

  @spec update(Cassette.t(), record, checkpoint, checkpoint | nil) :: Cassette.t()
  def update(cassette, record, checkpoint, parent_checkpoint \\ nil) do
    parent_record = cassette |> get_record!(parent_checkpoint)
    changes = module(cassette).delta(parent_record, record)

    changes =
      if parent_checkpoint,
        do: changes |> Map.put(:_parent, parent_checkpoint),
        else: changes

    put_in(cassette.deltas[checkpoint], changes)
    |> simplify_children(record, checkpoint)
    |> save
  end

  defp simplify_children(new_cassette, new_record, checkpoint) do
    new_cassette
    |> children_of(checkpoint)
    |> Enum.reduce(new_cassette, fn child_checkpoint, new_cassette ->
      child_record = new_cassette |> get_record(child_checkpoint)

      changes =
        module(new_cassette).delta(new_record, child_record)
        |> Map.put(:_parent, checkpoint)

      put_in(new_cassette.deltas[child_checkpoint], changes)
      |> simplify_children(child_record, child_checkpoint)
    end)
  end

  defp children_of(cassette, checkpoint) do
    for {child_checkpoint, %{_parent: ^checkpoint}} <- cassette.deltas,
        do: child_checkpoint
  end

  ### Utility functions for Changeset

  # Recursively transforms a record (struct) to maps.
  # FIXME
  def record_to_params(%Decimal{} = value), do: value

  def record_to_params(record) when is_struct(record) do
    record
    |> Map.from_struct()
    |> Utilities.Map.transform_values(&record_to_params/1)
  end

  def record_to_params(records) when is_list(records) do
    records
    |> Enum.map(&record_to_params/1)
  end

  def record_to_params(value), do: value

  # Recursively transforms changesets to list of changes.
  def changeset_to_delta(%Changeset{} = changeset),
    do: changeset.changes |> Utilities.Map.transform_values(&changeset_to_delta/1)

  def changeset_to_delta(changesets) when is_list(changesets),
    do: changesets |> Enum.map(&changeset_to_delta/1)

  def changeset_to_delta(changes), do: changes

  def changeset_fn(schema, options \\ []) do
    options =
      Keyword.validate!(options, [
        :fields,
        :embeds,
        assocs: [],
        include_fields: [],
        exclude_fields: []
      ])

    fields = options[:fields] || changeset_fields(schema, options)

    embed_fns =
      (options[:embeds] || schema.__schema__(:embeds))
      |> Keyword.new(&to_embed_name_fn(&1, schema))

    assoc_fns =
      options[:assocs]
      |> Keyword.new(&to_assoc_name_fn(&1, schema))

    fn record, params ->
      changeset =
        record
        |> Changeset.cast(params, fields, empty_values: [])

      changeset =
        embed_fns
        |> Enum.reduce(changeset, fn {embed_name, embed_fn}, changeset ->
          changeset |> Changeset.cast_embed(embed_name, with: embed_fn)
        end)

      assoc_fns
      |> Enum.reduce(changeset, fn {assoc_name, assoc_fn}, changeset ->
        changeset |> Changeset.cast_assoc(assoc_name, with: assoc_fn)
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
  end
end
