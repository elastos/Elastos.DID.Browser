defmodule BlockScoutWeb.TransactionDidlogController do
  use BlockScoutWeb, :controller

  import BlockScoutWeb.Models.GetTransactionTags, only: [get_transaction_with_addresses_tags: 2]
  import BlockScoutWeb.Account.AuthController, only: [current_user: 1]
  import BlockScoutWeb.Models.GetAddressTags, only: [get_address_tags: 2]

  alias BlockScoutWeb.{AccessHelpers, TransactionView}
  alias Explorer.{Chain, Market}
  alias Explorer.ExchangeRates.Token


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
        exchange_rate: Market.get_exchange_rate(Explorer.coin()) || Token.null(),
        current_user: current_user(conn),
        from_tags: get_address_tags(transaction.from_address_hash, current_user(conn)),
        to_tags: get_address_tags(transaction.to_address_hash, current_user(conn)),
        tx_tags:
          get_transaction_with_addresses_tags(
            transaction,
            current_user(conn)
          )
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