defmodule RateLimitError do
  defexception message: "Rate Limit Error"
end

defmodule MailProxy.Http do
  require Logger

  @error_body "{\"status\": \"error\"}"
  @success_body "{\"status\": \"success\"}"

  @error_response """
  HTTP/1.1 404\r
  Access-Control-Allow-Origin: *
  Content-Type: application/json\r
  Content-Length: #{byte_size(@error_body)}\r
  \r
  #{@error_body}
  """

  @email_sent_response """
  HTTP/1.1 201\r
  Access-Control-Allow-Origin: *
  Content-Type: application/json\r
  Content-Length: #{byte_size(@success_body)}\r
  \r
  #{@success_body}
  """

  @unauthorized """
  HTTP/1.1 401\r
  Access-Control-Allow-Origin: *
  Content-Type: application/json\r
  Content-Length: #{byte_size(@error_body)}\r
  \r
  #{@error_body}
  """

  @bad_request """
  HTTP/1.1 400\r
  Access-Control-Allow-Origin: *
  Content-Type: application/json\r
  Content-Length: #{byte_size(@error_body)}\r
  \r
  #{@error_body}
  """

  @rate_limit """
  HTTP/1.1 429\r
  Access-Control-Allow-Origin: *
  Content-Type: application/json\r
  Content-Length: #{byte_size(@error_body)}\r
  \r
  #{@error_body}
  """
  defp get_body_inner(sock) do
    :inet.setopts(sock, [{:packet, :raw}])
    {ok, body} = sock |> :gen_tcp.recv(0)
  end

  defp extract_val(val) do
    val |> String.codepoints() |> Enum.filter(&(Regex.match?(~r/[\S ]/,&1))) |> List.to_string
  end

  defp extract_name(val) do
    val |> String.split("\"") |> Enum.at(1)
  end

  defp is_wildcard(ips) do
    ips |> Enum.filter(&(&1 == "*")) |> length > 0
  end

  defp check_rate!(limiter), do: unless MailProxy.RateLimiter.allowed?(limiter), do: raise RateLimitError

  def start_link(port: port) do
    {:ok, socket} = :gen_tcp.listen(port, active: false, packet: :http_bin, reuseaddr: true)
    Logger.info("Accepting connections on port #{port}")
    rate = Application.fetch_env!(:mail_proxy, :rate)
    {:ok, conn} = MailProxy.RateLimiter.start_link(rate)

    {:ok, spawn_link(MailProxy.Http, :accept, [socket, conn])}
  end

  def get_content_length(sock) do
    case sock |> :gen_tcp.recv(0) do
      {:ok, {:http_header, _, "Content-Length", _, length}} -> length
      _ -> get_content_length(sock)
    end
  end

  def get_body(sock, n \\ 100) do
    if n == 0 do
      ""
    else
      case sock |> :gen_tcp.recv(0) do
        {:ok, :http_eoh} -> sock |> get_body_inner
        _ -> get_body(sock, n - 1)
      end
    end
  end

  def parse_body(body) do
    res = Regex.scan(~r/name="[\S]+"[\s\S]+?------/,  body |> Kernel.inspect())

    res |> Enum.reduce(%{},fn (r, acc) ->
      [param,_, input] = r
                          |> Enum.at(0)
                          |> String.split("\\r\\n")
                          |> Enum.take(3)

      name = param |> extract_val() |> extract_name
      value = input |> extract_val()

      Map.put(acc, name, value)
    end)
  end

  def handle_post(sock) do
    {:ok, body} = sock |> get_body()
    if body == "" do
      send_response(sock, @bad_request)
    else
      params = parse_body(body)
      if MailProxy.Email.verify(params) do
        MailProxy.Email.send_email(params["to"], params["subject"], params["body"])
        send_response(sock, @email_sent_response)
      else
        send_response(sock, @bad_request)
      end
    end
  end

  def handle_method(sock, method) do
    case method do
      :POST -> handle_post(sock)
        _ -> send_response(sock, @error_response)
    end
  end

  def accept(socket, limiter) do
    {:ok, sock} = :gen_tcp.accept(socket)

    spawn(fn ->
      try do
        check_rate!(limiter)
        ips = Application.fetch_env!(:mail_proxy, :whitelisted_ips)
        {:ok, {http_request, method, _path, _version}} = sock |> :gen_tcp.recv(0)

        if !is_wildcard(ips) do
          {:ok, {_, _, _, _, ipStr}} = sock |> :gen_tcp.recv(0)
          ip = ipStr |> String.split(":") |> Enum.at(0)

          if !(ips |> Enum.find(&(&1 == ip))) do
            send_response(sock, @unauthorized)
          else
            handle_method(sock, method)
          end
        else
          handle_method(sock, method)
        end
      rescue
        error in [RateLimitError] -> send_response(sock, @rate_limit)
        err -> (fn ->
          err |> IO.inspect()
          send_response(sock, @bad_request)
        end).()
      end
    end)

    accept(socket, limiter)
  end

  def send_response(socket, response) do
    :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  def child_spec(opts) do
    %{id: MailProxy.Http, start: {MailProxy.Http, :start_link, [opts]}}
  end
end
