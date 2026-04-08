defmodule Color.CSS.Calc do
  @moduledoc """
  A tiny `calc()` expression evaluator for CSS color components.

  Supports:

  * Numeric literals (`255`, `0.5`, `-1.2`).

  * Percentages (`50%`) — interpreted as the raw percent value
    (`50.0`), *not* as a fraction. Channel parsers in
    `Color.CSS` decide whether to scale.

  * The four arithmetic operators `+ - * /` with the conventional
    precedence and associativity.

  * Parenthesised sub-expressions.

  * Identifier references (`r`, `g`, `b`, `h`, `s`, `l`, `alpha`,
    …) that resolve against a `bindings` map. This is what makes
    relative color syntax (`oklch(from teal calc(l + 0.1) c h)`)
    work.

  * The `none` keyword — evaluated as `0.0`.

  Whitespace is ignored.

  ## Example

      iex> {:ok, ast} = Color.CSS.Calc.parse("255 / 2")
      iex> {:ok, value} = Color.CSS.Calc.evaluate(ast, %{})
      iex> value
      127.5

      iex> {:ok, ast} = Color.CSS.Calc.parse("l + 0.1")
      iex> {:ok, value} = Color.CSS.Calc.evaluate(ast, %{"l" => 0.5})
      iex> Float.round(value, 4)
      0.6

      iex> {:ok, ast} = Color.CSS.Calc.parse("(r + g + b) / 3")
      iex> {:ok, value} = Color.CSS.Calc.evaluate(ast, %{"r" => 200, "g" => 100, "b" => 50})
      iex> Float.round(value, 4)
      116.6667

  """

  @doc """
  Parses a calc() body into an AST.

  ### Arguments

  * `string` is the body of a `calc(...)` expression — everything
    between the outermost parens.

  ### Returns

  * `{:ok, ast}` on success.

  * `{:error, reason}` on a parse error.

  """
  def parse(string) when is_binary(string) do
    with {:ok, tokens} <- tokenize(string),
         {:ok, ast, []} <- parse_expr(tokens) do
      {:ok, ast}
    else
      {:ok, _ast, leftover} ->
        {:error, calc_error("unexpected leftover tokens #{inspect(leftover)}")}

      {:error, _} = err ->
        err
    end
  end

  @compile {:inline, calc_error: 1}
  defp calc_error(reason), do: %Color.ParseError{function: "calc", reason: reason}

  @doc """
  Evaluates a parsed `calc()` AST against a binding map.

  ### Arguments

  * `ast` is a value returned by `parse/1`.

  * `bindings` is a map from identifier strings to numeric values.

  ### Returns

  * `{:ok, float}` on success.

  * `{:error, reason}` on division by zero or unbound identifier.

  """
  def evaluate(ast, bindings) when is_map(bindings) do
    eval(ast, bindings)
  end

  # ---- AST -----------------------------------------------------------------
  #
  # The AST is a small recursive tagged tuple:
  #
  #   {:num, float}
  #   {:percent, float}
  #   {:ident, name}
  #   {:op, :+ | :- | :* | :/, lhs, rhs}
  #   {:neg, expr}                       — unary minus
  #
  # Parsing is plain recursive descent: expr -> term -> factor -> primary.

  defp parse_expr(tokens) do
    case parse_term(tokens) do
      {:ok, lhs, rest} -> parse_expr_tail(lhs, rest)
      {:error, _} = err -> err
    end
  end

  defp parse_expr_tail(lhs, [{:op, op} | rest]) when op in [:+, :-] do
    case parse_term(rest) do
      {:ok, rhs, rest2} -> parse_expr_tail({:op, op, lhs, rhs}, rest2)
      {:error, _} = err -> err
    end
  end

  defp parse_expr_tail(lhs, rest), do: {:ok, lhs, rest}

  defp parse_term(tokens) do
    case parse_factor(tokens) do
      {:ok, lhs, rest} -> parse_term_tail(lhs, rest)
      {:error, _} = err -> err
    end
  end

  defp parse_term_tail(lhs, [{:op, op} | rest]) when op in [:*, :/] do
    case parse_factor(rest) do
      {:ok, rhs, rest2} -> parse_term_tail({:op, op, lhs, rhs}, rest2)
      {:error, _} = err -> err
    end
  end

  defp parse_term_tail(lhs, rest), do: {:ok, lhs, rest}

  # Unary minus / plus.
  defp parse_factor([{:op, :-} | rest]) do
    case parse_factor(rest) do
      {:ok, expr, rest2} -> {:ok, {:neg, expr}, rest2}
      {:error, _} = err -> err
    end
  end

  defp parse_factor([{:op, :+} | rest]), do: parse_factor(rest)
  defp parse_factor(tokens), do: parse_primary(tokens)

  defp parse_primary([{:num, n} | rest]), do: {:ok, {:num, n}, rest}
  defp parse_primary([{:percent, p} | rest]), do: {:ok, {:percent, p}, rest}
  defp parse_primary([{:ident, name} | rest]), do: {:ok, {:ident, name}, rest}

  defp parse_primary([:lparen | rest]) do
    case parse_expr(rest) do
      {:ok, expr, [:rparen | rest2]} -> {:ok, expr, rest2}
      {:ok, _, _} -> {:error, calc_error("expected closing `)`")}
      {:error, _} = err -> err
    end
  end

  defp parse_primary([]), do: {:error, calc_error("unexpected end of expression")}

  defp parse_primary([token | _]),
    do: {:error, calc_error("unexpected token #{inspect(token)}")}

  # ---- evaluator -----------------------------------------------------------

  defp eval({:num, n}, _bindings), do: {:ok, n * 1.0}
  defp eval({:percent, p}, _bindings), do: {:ok, p * 1.0}

  defp eval({:neg, expr}, bindings) do
    case eval(expr, bindings) do
      {:ok, v} -> {:ok, -v}
      err -> err
    end
  end

  defp eval({:ident, "none"}, _bindings), do: {:ok, 0.0}

  defp eval({:ident, name}, bindings) do
    case Map.fetch(bindings, name) do
      {:ok, v} -> {:ok, v * 1.0}
      :error -> {:error, calc_error("unknown identifier `#{name}`")}
    end
  end

  defp eval({:op, op, lhs, rhs}, bindings) do
    with {:ok, l} <- eval(lhs, bindings),
         {:ok, r} <- eval(rhs, bindings) do
      apply_op(op, l, r)
    end
  end

  defp apply_op(:+, l, r), do: {:ok, l + r}
  defp apply_op(:-, l, r), do: {:ok, l - r}
  defp apply_op(:*, l, r), do: {:ok, l * r}
  defp apply_op(:/, _l, r) when r == 0, do: {:error, calc_error("division by zero")}
  defp apply_op(:/, l, r), do: {:ok, l / r}

  # ---- tokenizer -----------------------------------------------------------
  #
  # Tokens:
  #   {:num, float}
  #   {:percent, float}
  #   {:ident, name}
  #   {:op, :+ | :- | :* | :/}
  #   :lparen | :rparen

  defp tokenize(string) do
    string
    |> String.to_charlist()
    |> tok([])
  end

  defp tok([], acc), do: {:ok, Enum.reverse(acc)}

  defp tok([c | rest], acc) when c in [?\s, ?\t, ?\n], do: tok(rest, acc)

  defp tok([?( | rest], acc), do: tok(rest, [:lparen | acc])
  defp tok([?) | rest], acc), do: tok(rest, [:rparen | acc])

  defp tok([?+ | rest], acc), do: tok(rest, [{:op, :+} | acc])
  defp tok([?- | rest], acc), do: tok(rest, [{:op, :-} | acc])
  defp tok([?* | rest], acc), do: tok(rest, [{:op, :*} | acc])
  defp tok([?/ | rest], acc), do: tok(rest, [{:op, :/} | acc])

  defp tok([c | _] = chars, acc) when c in ?0..?9 or c == ?. do
    case take_number(chars) do
      {n, [?% | rest]} -> tok(rest, [{:percent, n} | acc])
      {n, rest} -> tok(rest, [{:num, n} | acc])
      :error -> {:error, calc_error("bad number")}
    end
  end

  defp tok([c | _] = chars, acc) when (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or c == ?_ do
    {ident, rest} = take_ident(chars)
    tok(rest, [{:ident, String.downcase(ident)} | acc])
  end

  defp tok([c | _], _),
    do: {:error, calc_error("unexpected char #{inspect(<<c::utf8>>)}")}

  defp take_number(chars) do
    {num_chars, rest} = Enum.split_while(chars, fn c -> c in ?0..?9 or c == ?. end)
    str = List.to_string(num_chars)

    case Float.parse(str) do
      {n, ""} -> {n, rest}
      _ -> :error
    end
  end

  defp take_ident(chars) do
    {ident_chars, rest} =
      Enum.split_while(chars, fn c ->
        (c >= ?a and c <= ?z) or
          (c >= ?A and c <= ?Z) or
          (c >= ?0 and c <= ?9) or
          c == ?_ or c == ?-
      end)

    {List.to_string(ident_chars), rest}
  end
end
