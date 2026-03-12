# Phoenix Component Attr/Slot Introspection

Investigation into reading Phoenix LiveView/Component `attr` and `slot` definitions at runtime.

**Date**: 2026-03-04
**Conclusion**: Full runtime introspection IS possible via the undocumented `__components__/0` function.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [What IS Possible at Runtime](#what-is-possible-at-runtime)
3. [What ISN'T Possible](#what-isnt-possible)
4. [How Phoenix Stores Attr/Slot Data Internally](#how-phoenix-stores-attrslot-data-internally)
5. [Approach 1: `__components__/0` (Recommended)](#approach-1-__components__0-recommended)
6. [Approach 2: AST Parsing via `Code.string_to_quoted/1` (Fallback)](#approach-2-ast-parsing-fallback)
7. [Approach 3: `Code.fetch_docs/1`](#approach-3-codefetch_docs1)
8. [Comparison of Approaches](#comparison-of-approaches)
9. [Recommended Implementation](#recommended-implementation)

---

## Executive Summary

Phoenix LiveView generates a `__components__/0` function on every module that uses `Phoenix.Component`. This function returns a map containing **complete attr and slot metadata** for every function component defined in the module, including names, types, defaults, `values` lists, required flags, and slot attributes. This is callable at runtime and contains everything Atelier needs.

---

## What IS Possible at Runtime

### 1. `Module.__components__/0` - Full Attr and Slot Metadata

Every module using `Phoenix.Component` (or `Phoenix.LiveComponent`) gets a generated `__components__/0` function. It returns a map keyed by function name:

```elixir
AtelierWeb.Components.Button.__components__()
# => %{
#   button: %{
#     kind: :def,
#     line: 23,
#     attrs: [
#       %{name: :type, type: :string, required: false, slot: nil, doc: nil, line: 13,
#         opts: [default: "button", values: ["button", "submit", "reset"]]},
#       %{name: :variant, type: :string, required: false, slot: nil, doc: nil, line: 14,
#         opts: [default: "primary", values: ["primary", "success", "error", "warning"]]},
#       %{name: :size, type: :string, required: false, slot: nil, doc: nil, line: 15,
#         opts: [default: "medium", values: ["xs", "small", "medium", "large", "xl"]]},
#       %{name: :disabled, type: :boolean, required: false, slot: nil, doc: nil, line: 16,
#         opts: [default: false]},
#       %{name: :class, type: :string, required: false, slot: nil, doc: nil, line: 17,
#         opts: [default: ""]},
#       %{name: :icon, type: :string, required: false, slot: nil, doc: nil, line: 18,
#         opts: [default: nil]},
#       %{name: :rest, type: :global, required: false, slot: nil, doc: nil, line: 19,
#         opts: []}
#     ],
#     slots: [
#       %{name: :inner_block, required: true, doc: nil, line: 21, opts: [],
#         attrs: [], validate_attrs: true}
#     ]
#   }
# }
```

**Each attr map contains:**
- `name` - atom, the attribute name
- `type` - atom or tuple, e.g. `:string`, `:boolean`, `:global`, `{:struct, MyStruct}`
- `required` - boolean
- `opts` - keyword list containing:
  - `default` - the default value (absent if not set)
  - `values` - list of allowed values (absent if not set)
  - `examples` - list of example values (absent if not set)
  - `include` - list of extra global attrs to include (for `:global` type)
- `slot` - nil for top-level attrs, slot name atom for slot attrs
- `doc` - string doc or nil
- `line` - source line number

**Each slot map contains:**
- `name` - atom, the slot name
- `required` - boolean
- `opts` - keyword list
- `doc` - string doc or nil
- `attrs` - list of attr maps (for named slots with declared attributes)
- `validate_attrs` - boolean
- `line` - source line number

### 2. Check if a module has components

```elixir
function_exported?(AtelierWeb.Components.Button, :__components__, 0)
# => true
```

### 3. `Code.fetch_docs/1` - Documentation with Attr Info

The generated docs for function components include attribute documentation:

```elixir
{:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(AtelierWeb.Components.Button)
# docs contains entries like:
# {{:function, :button, 1}, _line, _sig, %{"en" => "## Attributes\n\n* `type` ..."}, _meta}
```

This is a formatted string, not structured data, so it is less useful than `__components__/0`.

---

## What ISN'T Possible

### 1. `Module.get_attribute/2` at Runtime

Module attributes are only accessible during compilation. Calling it at runtime raises:

```elixir
Module.get_attribute(AtelierWeb.Components.Button, :__components__)
# ** (ArgumentError) could not call Module.get_attribute/2 because the module
#    AtelierWeb.Components.Button is already compiled.
```

### 2. `@__attrs__`, `@__slots__` at Runtime

These are accumulating module attributes used during compilation only. They are consumed by the `__on_definition__` callback and then deleted. They do not survive compilation.

### 3. Direct Access to Compilation Internals

The `@__components_calls__` attribute (which tracks where components are *called from*) is consumed by `__before_compile__` and converted into the `__phoenix_component_verify__/1` function. The raw call data is not directly accessible at runtime, but it is not needed for our use case anyway (it tracks callers, not definitions).

---

## How Phoenix Stores Attr/Slot Data Internally

This section documents the internal machinery (from `Phoenix.Component.Declarative`) for reference.

### Compilation Flow

1. **`use Phoenix.Component`** calls `Phoenix.Component.Declarative.__setup__/2`, which:
   - Registers accumulating module attributes: `@__attrs__`, `@__slot_attrs__`, `@__slots__`
   - Initializes `@__components__` as an empty map `%{}`
   - Registers `@on_definition` and `@before_compile` callbacks

2. **`attr :name, :type, opts`** macro calls `Declarative.__attr__!/6`, which:
   - Validates the type, options, values, defaults
   - Stores the attr as a map via `Module.put_attribute(module, :__attrs__, attr_map)`

3. **`slot :name, opts`** macro calls `Declarative.__slot__!/6`, which:
   - Validates options, processes any block (for slot attrs)
   - Stores via `Module.put_attribute(module, :__slots__, slot_map)`

4. **`def my_component(assigns)`** triggers the `__on_definition__` callback, which:
   - Pops accumulated `@__attrs__` and `@__slots__` (destructively reads and clears them)
   - Validates no duplicate names, no conflicts between attr and slot names
   - Stores into `@__components__` map: `%{my_component => %{kind: :def, attrs: [...], slots: [...], line: N}}`

5. **`__before_compile__`** callback generates:
   - `def __components__(), do: <escaped map>` -- this is the runtime-accessible function
   - Overridable wrapper functions that apply defaults and handle global attrs
   - `__phoenix_component_verify__/1` for cross-module compile-time validation

### Key Insight

The `__components__/0` function is generated in `__before_compile__` (line 711-715 of declarative.ex):

```elixir
def_components_ast =
  quote do
    def __components__() do
      unquote(Macro.escape(components))
    end
  end
```

This `Macro.escape(components)` embeds the full `@__components__` map as a literal in the compiled BEAM bytecode, making it available at runtime with zero overhead.

---

## Approach 1: `__components__/0` (Recommended)

### Code Example: Extract Attr Definitions

```elixir
defmodule Atelier.ComponentIntrospection do
  @doc """
  Returns attr and slot definitions for a component function in the given module.

  ## Examples

      iex> Atelier.ComponentIntrospection.get_component_info(
      ...>   AtelierWeb.Components.Button, :button)
      %{
        attrs: [%{name: :type, type: :string, ...}, ...],
        slots: [%{name: :inner_block, ...}]
      }
  """
  def get_component_info(module, function_name) do
    if function_exported?(module, :__components__, 0) do
      case module.__components__() do
        %{^function_name => info} -> {:ok, info}
        _ -> {:error, :function_not_found}
      end
    else
      {:error, :not_a_component_module}
    end
  end

  @doc """
  Returns attrs that have a `values` list defined (useful for combinatorial rendering).
  """
  def combinable_attrs(module, function_name) do
    with {:ok, %{attrs: attrs}} <- get_component_info(module, function_name) do
      attrs
      |> Enum.filter(fn attr ->
        values = Keyword.get(attr.opts, :values, [])
        values != []
      end)
      |> Enum.map(fn attr ->
        %{
          name: attr.name,
          type: attr.type,
          values: Keyword.fetch!(attr.opts, :values),
          default: Keyword.get(attr.opts, :default)
        }
      end)
    end
  end

  @doc """
  Generates all combinations of attrs that have `values` lists.
  Returns a list of maps, each representing one combination.
  """
  def generate_combinations(module, function_name) do
    attrs = combinable_attrs(module, function_name)

    Enum.reduce(attrs, [%{}], fn %{name: name, values: values}, acc ->
      for combo <- acc, value <- values, do: Map.put(combo, name, value)
    end)
  end

  @doc """
  Returns default assigns for a component (useful as a base for rendering).
  """
  def default_assigns(module, function_name) do
    with {:ok, %{attrs: attrs}} <- get_component_info(module, function_name) do
      for attr <- attrs,
          attr.type != :global,
          Keyword.has_key?(attr.opts, :default),
          into: %{} do
        {attr.name, attr.opts[:default]}
      end
    end
  end
end
```

### Usage: Render Every Variant x Size

```elixir
# In a LiveView or LiveComponent
combinations = Atelier.ComponentIntrospection.generate_combinations(
  AtelierWeb.Components.Button, :button
)
# => [
#   %{type: "button", variant: "primary", size: "xs"},
#   %{type: "button", variant: "primary", size: "small"},
#   ...60 total combinations...
# ]

defaults = Atelier.ComponentIntrospection.default_assigns(
  AtelierWeb.Components.Button, :button
)
# => %{type: "button", variant: "primary", size: "medium", disabled: false, class: "", icon: nil}

# For each combination, merge with defaults to get a complete assigns map
for combo <- combinations do
  assigns = Map.merge(defaults, combo)
  # render the component with these assigns...
end
```

### Trade-offs

| Pro | Con |
|-----|-----|
| Full structured data at runtime | `__components__/0` is undocumented / internal API |
| Zero overhead (compiled literal) | Could change in future LiveView versions |
| No file I/O needed | Requires module to be compiled and loaded |
| Includes values, defaults, types, docs | N/A |
| Works with any module using `Phoenix.Component` | N/A |

### Stability Assessment

The `__components__/0` function has been present since LiveView 0.18 (when the declarative API was introduced in [PR #1747](https://github.com/phoenixframework/phoenix_live_view/pull/1747)) and is used internally by Phoenix's own `__verify__` system for cross-module compile-time validation. It is also used by `Code.fetch_docs/1` integration. While technically undocumented, it is a stable internal interface that Phoenix itself depends on. The verification system (`__phoenix_component_verify__/1`) calls `submod.__components__()` at compile time, so removing it would break Phoenix's own validation. Risk of breaking changes is low.

---

## Approach 2: AST Parsing (Fallback)

If the module is not compiled/loaded (e.g., parsing source files on disk), parse the source with `Code.string_to_quoted/1` and walk the AST.

### Code Example

```elixir
defmodule Atelier.ComponentParser do
  @doc """
  Parses attr and slot declarations from an Elixir source string.
  Does not require the module to be compiled.
  """
  def parse_source(source) when is_binary(source) do
    {:ok, ast} = Code.string_to_quoted(source)

    {_, acc} = Macro.prewalk(ast, %{attrs: [], slots: []}, fn
      {:attr, _meta, [name, type | rest]} = node, acc ->
        opts = List.first(rest) || []
        attr = %{
          name: name,
          type: type,
          required: Keyword.get(opts, :required, false),
          default: Keyword.get(opts, :default, :__no_default__),
          values: Keyword.get(opts, :values, []),
          examples: Keyword.get(opts, :examples, []),
          doc: Keyword.get(opts, :doc)
        }
        {node, %{acc | attrs: [attr | acc.attrs]}}

      {:slot, _meta, [name | rest]} = node, acc ->
        opts = List.first(rest) || []
        slot = %{
          name: name,
          required: Keyword.get(opts, :required, false),
          doc: Keyword.get(opts, :doc)
        }
        {node, %{acc | slots: [slot | acc.slots]}}

      node, acc ->
        {node, acc}
    end)

    %{
      attrs: Enum.reverse(acc.attrs),
      slots: Enum.reverse(acc.slots)
    }
  end

  @doc "Parse from a file path."
  def parse_file(path) do
    path |> File.read!() |> parse_source()
  end
end
```

### Usage

```elixir
Atelier.ComponentParser.parse_file("lib/atelier_web/components/atelier/button.ex")
# => %{
#   attrs: [
#     %{name: :type, type: :string, default: "button", values: ["button", "submit", "reset"], ...},
#     %{name: :variant, type: :string, default: "primary", values: ["primary", ...], ...},
#     ...
#   ],
#   slots: [
#     %{name: :inner_block, required: true, doc: nil}
#   ]
# }
```

### Trade-offs

| Pro | Con |
|-----|-----|
| Works without compilation | Requires file I/O |
| No dependency on internal APIs | Does not resolve runtime expressions in opts |
| Works on any `.ex` file | Does not associate attrs with specific functions |
| Stable (Elixir AST is a public API) | More complex to implement correctly |
| | Does not handle `slot` blocks with nested `attr` calls |

---

## Approach 3: `Code.fetch_docs/1`

The generated docs embed attr info as formatted markdown text. This could be parsed, but it is fragile and lossy.

```elixir
{:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(AtelierWeb.Components.Button)

for {{:function, name, 1}, _line, _sig, %{"en" => doc}, _meta} <- docs do
  {name, doc}
end
# => [
#   {:button, "## Attributes\n\n* `type` (`:string`) - Defaults to `\"button\"`. Must be one of ..."}
# ]
```

**Not recommended** - the data is formatted text, not structured. Parsing it back into structured data would be brittle and information-lossy.

---

## Comparison of Approaches

| Criterion | `__components__/0` | AST Parsing | `Code.fetch_docs/1` |
|-----------|-------------------|-------------|---------------------|
| **Data completeness** | Full (all opts, types, defaults, values) | Full (from source) | Partial (formatted text) |
| **Structured data** | Yes (maps) | Yes (maps) | No (markdown string) |
| **Requires compilation** | Yes | No | Yes |
| **Requires file I/O** | No | Yes | No |
| **API stability** | Internal but stable | Public (Elixir AST) | Public |
| **Performance** | Instant (compiled literal) | Moderate (parse + walk) | Instant |
| **Handles runtime expressions** | Yes (resolved at compile time) | No (sees AST of expression) | N/A |
| **Associates attrs with functions** | Yes (keyed by function name) | No (flat list) | Yes (in doc per function) |

---

## Recommended Implementation

**Use `__components__/0` as the primary approach.** It provides complete, structured, runtime-accessible data with zero overhead. Fall back to AST parsing only for uncompiled source files.

### Implementation Sketch

```elixir
defmodule Atelier.ComponentIntrospection do
  @doc """
  Get component metadata, preferring runtime introspection, falling back to AST parsing.
  """
  def introspect(module, function_name) do
    cond do
      # Approach 1: Runtime introspection (preferred)
      Code.ensure_loaded?(module) and function_exported?(module, :__components__, 0) ->
        case module.__components__() do
          %{^function_name => info} ->
            {:ok, normalize(info)}

          _ ->
            {:error, :function_not_found}
        end

      # Approach 2: AST parsing fallback (for uncompiled modules)
      true ->
        {:error, :module_not_loaded}
    end
  end

  @doc """
  Get all component functions in a module.
  """
  def list_components(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__components__, 0) do
      {:ok, module.__components__()}
    else
      {:error, :not_a_component_module}
    end
  end

  @doc """
  Generate all value combinations for attrs that declare `values` lists.
  Useful for rendering a matrix of component variants.
  """
  def generate_combinations(module, function_name, opts \\ []) do
    with {:ok, info} <- introspect(module, function_name) do
      # Filter to only attrs with values lists
      combinable =
        info.attrs
        |> Enum.filter(fn attr ->
          values = Keyword.get(attr.opts, :values, [])
          values != [] and attr.type != :global
        end)
        |> maybe_filter_attrs(opts[:only])

      # Build base assigns from defaults
      defaults = build_defaults(info.attrs)

      # Generate cartesian product
      combinations =
        Enum.reduce(combinable, [%{}], fn attr, acc ->
          values = Keyword.fetch!(attr.opts, :values)
          for combo <- acc, value <- values, do: Map.put(combo, attr.name, value)
        end)

      # Merge each combination with defaults
      {:ok, Enum.map(combinations, &Map.merge(defaults, &1))}
    end
  end

  # --- Private helpers ---

  defp normalize(info) do
    %{
      kind: info.kind,
      attrs: info.attrs,
      slots: info.slots,
      line: info.line
    }
  end

  defp build_defaults(attrs) do
    for attr <- attrs,
        attr.type != :global,
        Keyword.has_key?(attr.opts, :default),
        into: %{} do
      {attr.name, attr.opts[:default]}
    end
  end

  defp maybe_filter_attrs(attrs, nil), do: attrs
  defp maybe_filter_attrs(attrs, names) do
    Enum.filter(attrs, fn attr -> attr.name in names end)
  end
end
```

### Integration with Existing `Atelier.Components` Module

The existing `Atelier.Components.read/1` function already reads component files and loads metadata. The introspection can be added alongside it:

```elixir
# In Atelier.Components.read/1, after loading the module:
module = Module.concat(AtelierWeb.Components, Macro.camelize(name))

component_info =
  if Code.ensure_loaded?(module) and function_exported?(module, :__components__, 0) do
    module.__components__()
  else
    %{}
  end

# Now component_info contains full attr/slot metadata for all function components
```

### For Dynamic Rendering in LiveView

```elixir
# In a LiveView that renders component previews:
def mount(_params, _session, socket) do
  module = AtelierWeb.Components.Button
  func = :button

  {:ok, combinations} =
    Atelier.ComponentIntrospection.generate_combinations(module, func,
      only: [:variant, :size]
    )

  {:ok, assign(socket, combinations: combinations, component_module: module, component_func: func)}
end

# In the HEEx template, render each combination:
# <div :for={combo <- @combinations}>
#   <%= apply(@component_module, @component_func, [Map.put(combo, :inner_block, [...])]) %>
# </div>
```

---

## References

- [Phoenix.Component documentation (v1.1.25)](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html)
- [Phoenix LiveView source: phoenix_component.ex](https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/phoenix_component.ex)
- [Phoenix LiveView source: phoenix_component/declarative.ex](https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/phoenix_component/declarative.ex)
- [PR #1747: Introduce declarative API for components](https://github.com/phoenixframework/phoenix_live_view/pull/1747)
- [Issue #2407: attr and slot for LiveComponent](https://github.com/phoenixframework/phoenix_live_view/issues/2407)
- [Elixir Forum: How does the attr macro associate the attribute to a function component?](https://elixirforum.com/t/how-does-the-attr-macro-associate-the-attribute-to-a-function-component/55425)
- [Sourceror: Utilities to manipulate Elixir source code](https://github.com/doorgan/sourceror)
