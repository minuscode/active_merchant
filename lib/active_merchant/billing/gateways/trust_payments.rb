module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class TrustPaymentsGateway < Gateway
      self.live_url = self.test_url = 'https://webservices.securetrading.net/json/'

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]

      self.homepage_url = 'http://www.trustpayments.com/'
      self.display_name = 'Trust Payments'

      self.money_format = :cents

      STANDARD_ERROR_CODE_MAPPING = {}

      def initialize(options={})
        requires!(options, :account, :login, :password)
        @account, @login, @password = options.values_at(:account, :login, :password)
        super
      end

      def purchase(money, payment, options={})
        # TODO: this if needed
        post = {}
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit('sale', post)
      end

      def authorize(money, payment, options={})
        #requires!(options, :login)
        post = init_post(options)
        #binding.pry

        post["request"] = [{
          "currencyiso3a": "USD",
          "requesttypedescriptions": ["AUTH"],
          "authmethod": "PRE",
          "sitereference": @account,
          "baseamount": "#{money}",
          "orderreference": "My_Order_123_PRE_3",
          "accounttypedescription": "ECOM",
          "pan": payment.number,
          "expirydate": ('%02d/%s' % [payment.month, payment.year]),
          "securitycode": payment.verification_value,
          "settlestatus": "2"
        }]

        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit('authonly', post)
      end

      def capture(money, authorization, options={})
        #requires!(options, :login)
        post = init_post(options)

        post["request"] = [{
          "requesttypedescriptions": ["TRANSACTIONUPDATE"],
          "filter":{
            "sitereference": [{"value":"#{@account}"}],
            "transactionreference": [{"value":"#{authorization}"}]
          },
          "updates":{"settlestatus":"0"}
        }]

        commit('capture', post)
      end

      def refund(money, authorization, options={})
        commit('refund', post)
      end

      def void(authorization, options={})
        commit('void', post)
      end

      def verify(credit_card, options={})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript
      end

      private

      def add_customer_data(post, options)
      end

      def add_address(post, creditcard, options)
      end

      def add_invoice(post, money, options)
        post[:amount] = amount(money)
        post[:currency] = (options[:currency] || currency(money))
      end

      def add_payment(post, payment)
      end

      def parse(body)
        return {} if body.blank?

        JSON.parse(body)
      end

      def basic_auth
        Base64.strict_encode64("#{@login}:#{@password}")
      end

      def request_headers
        headers = {
          'Content-Type' => 'application/json',
          'Accept' => 'application/json',
          'Authorization' => "Basic #{basic_auth}"
        }
        headers
      end

      def commit(action, parameters)
        url = (test? ? test_url : live_url)

        #parameters[:something] = "yes"
        #parameters[:other] = "la"
        #puts post_data(action, parameters)
        #binding.pry

        response = parse(ssl_post(url, post_data(action, parameters), request_headers))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          avs_result: AVSResult.new(code: response["some_avs_response_key"]),
          cvv_result: CVVResult.new(response["some_cvv_response_key"]),
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def success_from(response)
        # TODO: something here
        response["response"].first["errormessage"] == "Ok"
      end

      def message_from(response)
      end

      def authorization_from(response)
        response["response"].first["transactionreference"]
      end

      def init_post(options = {})
        post = {
          "version": "1.00",
          "alias": options[:login] || @login
        }
        post
      end

      def post_data(action, parameters = {})
        JSON.generate(parameters)
      end

      def error_code_from(response)
        unless success_from(response)
          # TODO: lookup error code for this response
        end
      end
    end
  end
end
