# `Color.Palette.Visualizer.Standalone` runs the visualizer as
# a self-contained Bandit web server. It is only defined when
# `:bandit` is available (which transitively pulls in `:plug`),
# so consumer apps that don't need a standalone dev server
# don't get compiler warnings about missing modules. When
# `:bandit` isn't installed, this module simply doesn't exist
# and any call to it raises the standard
# `UndefinedFunctionError`.
if Code.ensure_loaded?(Bandit) do
  defmodule Color.Palette.Visualizer.Standalone do
    @moduledoc """
    A tiny helper that runs `Color.Palette.Visualizer` as a
    standalone web server for local development.

    Requires `:bandit` in your project's deps. This module is
    only compiled when `:bandit` is present — without it,
    `Color.Palette.Visualizer.Standalone` doesn't exist as a
    module and calling its functions raises
    `UndefinedFunctionError`.

        Color.Palette.Visualizer.Standalone.start(port: 4001)
        # Visit http://localhost:4001

    To stop the server, call
    `Color.Palette.Visualizer.Standalone.stop/1` with the PID
    returned from `start/1`.

    """

    @doc """
    Starts the visualizer on the given port.

    ### Options

    * `:port` — TCP port to listen on. Default `4001`.

    * `:ip` — IP address to bind to. Default `:loopback` (only
      accessible from localhost). Pass `:any` to bind on all
      interfaces.

    ### Returns

    * `{:ok, pid}` on success.

    * `{:error, reason}` on failure — most commonly a port-in-use
      error.

    """
    @spec start(keyword()) :: {:ok, pid()} | {:error, term()}
    def start(options \\ []) do
      port = Keyword.get(options, :port, 4001)
      ip = Keyword.get(options, :ip, :loopback)

      bandit_options = [
        plug: Color.Palette.Visualizer,
        port: port,
        ip: ip_tuple(ip)
      ]

      Bandit.start_link(bandit_options)
    end

    @doc """
    Returns a child spec suitable for embedding under a
    supervision tree.

    ### Options

    See `start/1`.

    ### Returns

    * A child specification map.

    """
    @spec child_spec(keyword()) :: Supervisor.child_spec()
    def child_spec(options \\ []) do
      port = Keyword.get(options, :port, 4001)
      ip = Keyword.get(options, :ip, :loopback)

      %{
        id: __MODULE__,
        start:
          {Bandit, :start_link, [[plug: Color.Palette.Visualizer, port: port, ip: ip_tuple(ip)]]},
        type: :supervisor
      }
    end

    @doc """
    Stops a standalone server started by `start/1`.

    ### Arguments

    * `pid` — the process identifier returned by `start/1`.

    ### Returns

    * `:ok`.

    """
    @spec stop(pid()) :: :ok
    def stop(pid) when is_pid(pid) do
      _ = Supervisor.stop(pid)
      :ok
    end

    # ---- helpers ------------------------------------------------------------

    defp ip_tuple(:loopback), do: {127, 0, 0, 1}
    defp ip_tuple(:any), do: {0, 0, 0, 0}
    defp ip_tuple({_, _, _, _} = tuple), do: tuple
  end
end
