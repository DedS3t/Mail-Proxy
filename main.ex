children = [
  {
    MailProxy.Http,
    port: 8080
  },
]

opts = [strategy: :one_for_one, name: Http.Supervisor]

{:ok, pid} = Supervisor.start_link(children, opts)

Supervisor.count_children(pid) |> IO.inspect()

receive do
  {:ok, _} -> IO.puts ""
end
