defmodule BlockScoutWeb.TransactionDidlogController do
  use BlockScoutWeb, :controller

  import BlockScoutWeb.Chain, only: [paging_options: 1, next_page_params: 3, split_list_by_page: 1]

  alias BlockScoutWeb.{AccessHelpers, TransactionDidlogView, TransactionView}
  alias Explorer.{Chain, Market}
  alias Explorer.ExchangeRates.Token
  alias Phoenix.View


  def index(conn, %{"transaction_id" => transaction_hash_string} = params) do
    with {:ok, transaction_hash} <- Chain.string_to_transaction_hash(transaction_hash_string),
         {:ok, transaction} <-
           Chain.hash_to_transaction(
             transaction_hash,
             necessity_by_association: %{
               :block => :optional,
               [created_contract_address: :names] => :optional,
               [from_address: :names] => :required,
               [to_address: :names] => :optional,
               [to_address: :smart_contract] => :optional,
               :token_transfers => :optional
             }
           ),
         {:ok, didlog} <- Chain.didlog_to_transaction(transaction_hash),
         didlog = Poison.decode!(didlog),
         {:ok, false} <- AccessHelpers.restricted_access?(to_string(transaction.from_address_hash), params),
         {:ok, false} <- AccessHelpers.restricted_access?(to_string(transaction.to_address_hash), params) do
      render(
        conn,
        "index.html",
        block_height: Chain.block_height(),
        show_token_transfers: Chain.transaction_has_token_transfers?(transaction_hash),
        current_path: current_path(conn),
        transaction: transaction,
        didlog: didlog,
        exchange_rate: Market.get_exchange_rate(Explorer.coin()) || Token.null()
      )
    else
      {:restricted_access, _} ->
        conn
        |> put_status(404)
        |> put_view(TransactionView)
        |> render("not_found.html", transaction_hash: transaction_hash_string)

      :error ->
        conn
        |> put_status(422)
        |> put_view(TransactionView)
        |> render("invalid.html", transaction_hash: transaction_hash_string)

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(TransactionView)
        |> render("not_found.html", transaction_hash: transaction_hash_string)
    end
  end

end