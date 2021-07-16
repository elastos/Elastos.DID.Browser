defmodule Indexer.Block.Fetcher.Receipts do
  @moduledoc """
  Fetches transaction receipts after the transactions have been fetched with the blocks in `Indexer.BlockFetcher`.
  """

  require Logger

  alias Indexer.Block

  def fetch(%Block.Fetcher{} = _state, []), do: {:ok, %{logs: [], receipts: [], didlog: []}}

  def fetch(
        %Block.Fetcher{json_rpc_named_arguments: json_rpc_named_arguments} = state,
        transaction_params
      ) do
    Logger.debug("fetching transaction receipts", count: Enum.count(transaction_params))
    stream_opts = [max_concurrency: state.receipts_concurrency, timeout: :infinity]

    transaction_params
    |> Enum.chunk_every(state.receipts_batch_size)
    |> Task.async_stream(&EthereumJSONRPC.fetch_transaction_receipts(&1, json_rpc_named_arguments), stream_opts)
    |> Enum.reduce_while({:ok, %{logs: [], receipts: [], didlog: []}}, fn
      {:ok, {:ok, %{logs: logs, receipts: receipts, didlog: didlog}}}, {:ok, %{logs: acc_logs, receipts: acc_receipts, didlog: acc_didlog}} ->
        {:cont, {:ok, %{logs: acc_logs ++ logs, receipts: acc_receipts ++ receipts, didlog: acc_didlog ++ didlog}}}

      {:ok, {:error, reason}}, {:ok, _acc} ->
        {:halt, {:error, reason}}

      {:error, reason}, {:ok, _acc} ->
        {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, receipt_params} -> {:ok, set_block_number_to_logs(receipt_params, transaction_params)}
      other -> other
    end
  end

  def put(transactions_params, receipts_params) when is_list(transactions_params) and is_list(receipts_params) do
    transaction_hash_to_receipt_params =
      Enum.into(receipts_params, %{}, fn %{transaction_hash: transaction_hash} = receipt_params ->
        {transaction_hash, receipt_params}
      end)

    Enum.map(transactions_params, fn %{hash: transaction_hash} = transaction_params ->
      receipts_params = Map.fetch!(transaction_hash_to_receipt_params, transaction_hash)
      merged_params = Map.merge(transaction_params, receipts_params)

      if transaction_params[:created_contract_address_hash] && is_nil(receipts_params[:created_contract_address_hash]) do
        Map.put(merged_params, :created_contract_address_hash, transaction_params[:created_contract_address_hash])
      else
        merged_params
      end
    end)
  end


  def add_did_log(transactions_with_receipts, didlogs) when is_list(transactions_with_receipts) and is_list(didlogs) do

    didlogs = for x <- didlogs, !is_nil(x), do: x

    if didlogs != [] do
      transaction_hash_to_didlog =
        Enum.into(didlogs, %{}, fn %{"transactionHash" => transactionHash} = didlog ->
          {transactionHash, didlog}
        end)
      
      Enum.map(transactions_with_receipts, fn %{hash: transaction_hash} = transaction_params ->
        didlogs = Map.fetch!(transaction_hash_to_didlog, transaction_hash)
        payload = EthereumJSONRPC.fetch_did_info(didlogs["did"], transaction_hash)
        didlogs = Map.merge(didlogs, %{payload: payload})
        merged_params = Map.merge(transaction_params, %{didlog: Poison.encode!(didlogs)})
        merged_params = Map.merge(merged_params, %{did: didlogs["did"]})
        #require Logger
          #Logger.warn("-=-=-=-=-=-=-=-=-==-=-add_did_log==-=-=-=-=-=-=-=: #{inspect(merged_params)}")
        merged_params
      end)
    else
      transactions_with_receipts
    end

  end

  defp set_block_number_to_logs(%{logs: logs} = params, transaction_params) do
    logs_with_block_numbers =
      Enum.map(logs, fn %{transaction_hash: transaction_hash, block_number: block_number} = log_params ->
        if is_nil(block_number) do
          transaction =
            Enum.find(transaction_params, fn transaction ->
              transaction[:hash] == transaction_hash
            end)

          %{log_params | block_number: transaction[:block_number]}
        else
          log_params
        end
      end)

    %{params | logs: logs_with_block_numbers}
  end
end
