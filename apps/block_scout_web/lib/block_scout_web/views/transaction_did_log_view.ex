defmodule BlockScoutWeb.TransactionDidlogView do
  use BlockScoutWeb, :view
  @dialyzer :no_match

  alias Explorer.Chain.Log

  def decode(log, transaction) do
    Log.decode(log, transaction)
  end

  def decode_payload(payload) do
    if payload != "" && payload != nil do
      #payload = Enum.at(payload, 0, "")
      if String.contains?(payload, "did:elastos:") do
        payload
      else
        {:ok, payload_result} = Base.url_decode64(payload, padding: false)
        payload_result
      end
    end
  end
end
