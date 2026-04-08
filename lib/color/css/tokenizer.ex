defmodule Color.CSS.Tokenizer do
  @moduledoc """
  A small, paren-aware tokenizer for the bodies of CSS color
  functions (`rgb(...)`, `hsl(...)`, `lab(...)`, `color(...)`,
  `device-cmyk(...)`, etc).

  The tokenizer walks the input character-by-character, splits at
  whitespace and commas at depth zero, and groups any nested
  function call (e.g. `calc(255 / 2)`) into a single
  `{:func, name, body}` token. This is enough structure for
  `Color.CSS` to dispatch each component to the right resolver
  without re-parsing the surrounding context.

  ## Token shapes

  * `{:number, float}` — a bare number, e.g. `255`, `0.5`, `-1.2`.
  * `{:percent, float}` — a percentage value (the raw percent
    number, *not* divided by 100), e.g. `{:percent, 50.0}` for `50%`.
  * `{:hue, float, unit}` — an angle with an explicit unit
    (`:deg`, `:rad`, `:grad`, `:turn`).
  * `:none` — the literal `none` keyword.
  * `{:ident, name}` — a bare identifier (`from`, `in`, `red`,
    `display-p3`, or a relative-color component reference).
  * `{:func, name, body}` — a parenthesised function call,
    name lower-cased, body retained as a string for the consumer
    to parse.
  * `{:hex, hex}` — `#rrggbb` etc, with the leading `#` stripped.
  * `{:slash}` — the `/` separator that introduces an alpha value.

  """

  @doc """
  Tokenizes a CSS color function body.

  ### Arguments

  * `string` is the body of a CSS function — everything between
    its outermost `(` and `)`.

  ### Returns

  * `{:ok, [token]}` on success.

  * `{:error, reason}` on syntax errors (currently only unbalanced
    parens).

  ### Examples

      iex> Color.CSS.Tokenizer.tokenize("255 0 0")
      {:ok, [{:number, 255.0}, {:number, 0.0}, {:number, 0.0}]}

      iex> Color.CSS.Tokenizer.tokenize("none 0 0")
      {:ok, [:none, {:number, 0.0}, {:number, 0.0}]}

      iex> Color.CSS.Tokenizer.tokenize("calc(255 / 2) 0 0")
      {:ok, [{:func, "calc", "255 / 2"}, {:number, 0.0}, {:number, 0.0}]}

      iex> Color.CSS.Tokenizer.tokenize("from red r g b")
      {:ok,
       [{:ident, "from"}, {:ident, "red"}, {:ident, "r"}, {:ident, "g"}, {:ident, "b"}]}

      iex> Color.CSS.Tokenizer.tokenize("255 0 0 / 50%")
      {:ok, [{:number, 255.0}, {:number, 0.0}, {:number, 0.0}, {:slash}, {:percent, 50.0}]}

      iex> Color.CSS.Tokenizer.tokenize("display-p3 1 0 0")
      {:ok, [{:ident, "display-p3"}, {:number, 1.0}, {:number, 0.0}, {:number, 0.0}]}

  """
  def tokenize(string) when is_binary(string) do
    case raw_tokens(string) do
      {:ok, raws} ->
        raws
        |> Enum.reduce_while({:ok, []}, fn raw, {:ok, acc} ->
          case classify(raw) do
            {:ok, token} -> {:cont, {:ok, [token | acc]}}
            {:error, _} = err -> {:halt, err}
          end
        end)
        |> case do
          {:ok, list} -> {:ok, Enum.reverse(list)}
          {:error, _} = err -> err
        end

      {:error, _} = err ->
        err
    end
  end

  # ---- raw splitting (paren + comma + whitespace aware) -------------------

  defp raw_tokens(string) do
    string
    |> String.to_charlist()
    |> walk([], [], 0, [])
  end

  # walk(remaining, current_token, accumulated_tokens, paren_depth, paren_buffer)
  # current_token is the chars of the token currently being built (depth 0).
  # When we open a paren we start collecting into paren_buffer until depth
  # returns to 0; the function call is then a single token.

  defp walk([], [], acc, 0, _) do
    {:ok, Enum.reverse(acc)}
  end

  defp walk([], current, acc, 0, _) do
    {:ok, Enum.reverse([finalize(current) | acc])}
  end

  defp walk([], _current, _acc, _depth, _) do
    {:error, %Color.ParseError{function: "tokenizer", reason: "unbalanced parens"}}
  end

  # Slash at depth 0: emit it as its own token.
  defp walk([?/ | rest], current, acc, 0, _) do
    acc =
      case current do
        [] -> acc
        _ -> [finalize(current) | acc]
      end

    walk(rest, [], ["/" | acc], 0, [])
  end

  # Comma or whitespace at depth 0: end the current token (if any).
  defp walk([c | rest], current, acc, 0, _) when c in [?\s, ?\t, ?\n, ?,] do
    case current do
      [] -> walk(rest, [], acc, 0, [])
      _ -> walk(rest, [], [finalize(current) | acc], 0, [])
    end
  end

  # Open paren: start collecting a function call. The chars before
  # the `(` are the function name (already in `current`). `buf` is
  # kept in *reversed* order so that we can prepend cheaply, just
  # like `current`. We reverse and assemble at the closing paren.
  defp walk([?( | rest], current, acc, 0, _) do
    name = finalize(current)
    # Pre-load buf with the literal "(" and the function name in
    # *reversed* order so that the eventual reverse-and-join gives
    # `name(`...
    walk(rest, [], acc, 1, [?(, name])
  end

  defp walk([?( | rest], current, acc, depth, buf) do
    walk(rest, current, acc, depth + 1, [?( | buf])
  end

  defp walk([?) | rest], _current, acc, 1, buf) do
    full = [?) | buf] |> Enum.reverse() |> IO.iodata_to_binary()
    walk(rest, [], [full | acc], 0, [])
  end

  defp walk([?) | rest], current, acc, depth, buf) when depth > 1 do
    walk(rest, current, acc, depth - 1, [?) | buf])
  end

  # Inside parens: just accumulate (still reversed).
  defp walk([c | rest], current, acc, depth, buf) when depth > 0 do
    walk(rest, current, acc, depth, [c | buf])
  end

  # Normal char at depth 0: extend the current token.
  defp walk([c | rest], current, acc, 0, _) do
    walk(rest, [c | current], acc, 0, [])
  end

  defp finalize(chars) do
    chars |> Enum.reverse() |> List.to_string()
  end

  # ---- classification ------------------------------------------------------

  defp classify("/"), do: {:ok, {:slash}}

  defp classify("none"), do: {:ok, :none}
  defp classify("None"), do: {:ok, :none}
  defp classify("NONE"), do: {:ok, :none}

  defp classify("#" <> hex), do: {:ok, {:hex, hex}}

  defp classify(token) do
    cond do
      hue_token?(token) ->
        classify_hue(token)

      String.ends_with?(token, "%") ->
        classify_percent(token)

      function_call?(token) ->
        classify_function(token)

      number?(token) ->
        classify_number(token)

      identifier?(token) ->
        {:ok, {:ident, String.downcase(token)}}

      true ->
        {:error,
         %Color.ParseError{function: "tokenizer", reason: "unrecognised token #{inspect(token)}"}}
    end
  end

  defp function_call?(token) do
    case Regex.run(~r/^([a-zA-Z][a-zA-Z0-9-]*)\((.*)\)$/s, token) do
      [_, _, _] -> true
      _ -> false
    end
  end

  defp classify_function(token) do
    [_, name, body] = Regex.run(~r/^([a-zA-Z][a-zA-Z0-9-]*)\((.*)\)$/s, token)
    {:ok, {:func, String.downcase(name), body}}
  end

  defp number?(token) do
    case Float.parse(token) do
      {_, ""} -> true
      _ -> false
    end
  end

  defp classify_number(token) do
    case Float.parse(token) do
      {n, ""} ->
        {:ok, {:number, n}}

      _ ->
        {:error,
         %Color.ParseError{function: "tokenizer", reason: "invalid number #{inspect(token)}"}}
    end
  end

  defp classify_percent(token) do
    case Float.parse(String.trim_trailing(token, "%")) do
      {n, ""} ->
        {:ok, {:percent, n}}

      _ ->
        {:error,
         %Color.ParseError{
           function: "tokenizer",
           reason: "invalid percentage #{inspect(token)}"
         }}
    end
  end

  defp hue_token?(token) do
    String.ends_with?(token, "deg") or
      String.ends_with?(token, "rad") or
      String.ends_with?(token, "grad") or
      String.ends_with?(token, "turn")
  end

  defp classify_hue(token) do
    {num, unit} =
      cond do
        String.ends_with?(token, "grad") -> {String.trim_trailing(token, "grad"), :grad}
        String.ends_with?(token, "deg") -> {String.trim_trailing(token, "deg"), :deg}
        String.ends_with?(token, "rad") -> {String.trim_trailing(token, "rad"), :rad}
        String.ends_with?(token, "turn") -> {String.trim_trailing(token, "turn"), :turn}
      end

    case Float.parse(num) do
      {n, ""} ->
        {:ok, {:hue, n, unit}}

      _ ->
        {:error,
         %Color.ParseError{function: "tokenizer", reason: "invalid hue #{inspect(token)}"}}
    end
  end

  defp identifier?(token) do
    Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_-]*$/, token)
  end
end
