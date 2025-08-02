class Provider::ExchangerateApi < Provider
  include ExchangeRateConcept

  # Subclass so errors caught in this provider are raised as Provider::ExchangerateApi::Error
  Error = Class.new(Provider::Error)
  InvalidExchangeRateError = Class.new(Error)

  def initialize(api_key = nil)
    @api_key = api_key # Optional for free tier
  end

  def healthy?
    with_provider_response do
      response = client.get("#{base_url}/latest/USD")
      JSON.parse(response.body).dig("result") == "success"
    end
  end

  def usage
    # Free tier: 1500 requests per month
    # Return a mock usage data since we can't get exact usage without API key
    UsageData.new(
      used: 0,
      limit: 1500,
      utilization: 0.0,
      plan: "free"
    )
  end

  # ================================
  #          Exchange Rates
  # ================================

  def fetch_exchange_rate(from:, to:, date:)
    with_provider_response do
      endpoint = date == Date.current ? "latest" : "history"
      url = "#{base_url}/#{endpoint}/#{from}"

      response = client.get(url) do |req|
        req.params["base"] = from
        if endpoint == "history"
          req.params["date"] = date.strftime("%Y-%m-%d")
        end
      end

      data = JSON.parse(response.body)

      unless data["result"] == "success"
        raise InvalidExchangeRateError, "API error: #{data['error-type']}"
      end

      rate_value = data.dig("conversion_rates", to)
      raise InvalidExchangeRateError, "No rate found for #{from} to #{to} on #{date}" if rate_value.nil?

      Rate.new(date: date.to_date, from: from, to: to, rate: rate_value)
    end
  end

  def fetch_exchange_rates(from:, to:, start_date:, end_date:)
    # ExchangeRate-API doesn't support date ranges in a single request
    # We'll need to make individual requests for each date
    dates = (start_date..end_date).to_a

    rates = dates.map do |date|
      begin
        fetch_exchange_rate(from: from, to: to, date: date)
      rescue => e
        Rails.logger.warn("Failed to fetch rate for #{from} to #{to} on #{date}: #{e.message}")
        nil
      end
    end.compact

    rates
  end

  private

    def base_url
      if @api_key.present?
        "https://v6.exchangerate-api.com/v6/#{@api_key}"
      else
        "https://open.er-api.com/v6"
      end
    end

    def client
      @client ||= Faraday.new(url: base_url) do |faraday|
        faraday.request(:retry, {
          max: 2,
          interval: 0.05,
          interval_randomness: 0.5,
          backoff_factor: 2
        })

        faraday.response :raise_error
        faraday.headers["User-Agent"] = "maybe_app"
      end
    end
end
