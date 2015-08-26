module ActivePayment
  class Gateway
    attr_accessor :gateway, :purchase_token

    def initialize(gateway)
      case gateway
      when 'paypal_express_checkout'
        @gateway = ActivePayment::Gateways::PaypalExpressCheckout.new
      when 'paypal_adaptive_payment'
        @gateway = ActivePayment::Gateways::PaypalAdaptivePayment.new
      else
        fail 'gateway not supported'
      end
    end

    def setup_purchase(sales, ip_address)
      url = @gateway.setup_purchase(sales)
      @purchase_token = @gateway.purchase_token
      create_transactions(ip_address)

      url
    end

    def verify_purchase(external_id, raw_data)
      transactions = ActivePayment::Transaction.where(external_id: external_id)
      fail ActivePayment::NoTransactionError unless transactions.size > 0

      if @gateway.verify_purchase(raw_data)
        transactions_success(transactions)
      else
        transactions_error(transactions)
        fail ActivePayment::InvalidGatewayResponseError
      end
    end

    def external_id_from_request(request)
      @gateway.external_id_from_request(request)
    end

    def livemode?
      @gateway.livemode?
    end

    private

    def create_transactions(ip_address)
      fail 'You must called setup_purchase before creating a transaction' unless @gateway.sales

      @gateway.sales.each do |sale|
        ActivePayment::Services::TransactionCreate.new({
          currency: "USD",
          gateway: @gateway.class.to_s,
          amount: sale.amount_in_cents,
          ip_address: ip_address,
          payee_id: sale.payee.id,
          payer_id: sale.payer.id,
          payable_id: sale.payable.id,
          reference_number: sale.payable.reference,
          external_id: @purchase_token,
        }).call
      end
    end

    def transactions_success(transactions)
      transactions.each do |transaction|
        ActivePayment::Services::TransactionSuccess.new(transaction.id).call
      end
    end

    def transactions_error(transactions)
      transactions.each do |transaction|
        ActivePayment::Services::TransactionError.new(transaction.id).call
      end
    end
  end
end