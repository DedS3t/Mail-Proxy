defmodule MailProxy.Email do
  import Bamboo.Email

  def send_email(to, subject, data) do
    new_email(
      to: to,
      from: "mailer@ezml.io",
      subject: subject,
      text_body: data
    ) |> MailProxy.Mailer.deliver_now()
  end


  def verify(map) do
    map |> Map.has_key?("to") && map |> Map.has_key?("subject") && map |> Map.has_key?("body")
  end
end
