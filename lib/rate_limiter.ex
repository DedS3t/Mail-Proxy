defmodule MailProxy.RateLimiter do
  use GenServer

  @doc """
  Starts the RateLimiter
  """
  def start_link(rate) do
    GenServer.start_link(__MODULE__, rate)
  end

  @doc """
  Check if incoming request should be allowed. Updates respective rates
  """
  def allowed?(limiter, ip \\ "") do
    GenServer.call(limiter, {:request, ip}) == :ok
  end

  @impl true
  def init(rate) do
    {:ok, %{reqs: 0, lastUpdated: :os.system_time(:second), rate: rate}}
  end

  @impl true
  def handle_call({:request, _ip}, _from, state) do
    if state[:rate] == 0 do
      {:reply, :ok, state}
    else
      time = :os.system_time(:second)
      if time - state[:lastUpdated] > 60 do
        {:reply, :ok, %{reqs: 1, lastUpdated: time, rate: state[:rate]}}
      else
        if state[:reqs] >= state[:rate] do
          {:reply, :error, state}
        else
          {:reply, :ok, Map.put(state, :reqs, state[:reqs] + 1)}
        end
      end
    end
  end
end
