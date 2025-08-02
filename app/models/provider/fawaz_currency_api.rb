class Provider::FawazCurrencyApi < Provider
  include ExchangeRateConcept

  # Subclass so errors caught in this provider are raised as Provider::FawazCurrencyApi::Error
  Error = Class.new(Provider::Error)
  InvalidExchangeRateError = Class.new(Error)

  def initialize
    # No API key required for this free API
  end

  def healthy?
    with_provider_response do
      response = client.get("https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies.json")
      JSON.parse(response.body).is_a?(Hash)
    end
  end

  def usage
    # Free API with no rate limits
    UsageData.new(
      used: 0,
      limit: Float::INFINITY,
      utilization: 0.0,
      plan: "free"
    )
  end

  # ================================
  #          Exchange Rates
  # ================================

  def fetch_exchange_rate(from:, to:, date:)
    with_provider_response do
      # Use latest or specific date
      date_param = date == Date.current ? "latest" : date.strftime("%Y-%m-%d")
      url = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@#{date_param}/v1/currencies/#{from.downcase}.json"

      response = client.get(url)
      data = JSON.parse(response.body)

      # The API returns rates relative to the "from" currency
      rate_key = from.downcase
      rates = data.dig(rate_key)

      raise InvalidExchangeRateError, "No rates found for #{from}" if rates.nil?

      rate_value = rates.dig(to.downcase)
      raise InvalidExchangeRateError, "No rate found for #{from} to #{to} on #{date}" if rate_value.nil?

      Rate.new(date: date.to_date, from: from, to: to, rate: rate_value)
    end
  end

  def fetch_exchange_rates(from:, to:, start_date:, end_date:)
    with_provider_response do
      # This API doesn't support date ranges in a single request
      # We'll need to make individual requests for each date
      dates = (start_date..end_date).to_a

      rates = dates.map do |date|
        begin
          response = fetch_exchange_rate(from: from, to: to, date: date)
          response.success? ? response.data : nil
        rescue => e
          Rails.logger.warn("Failed to fetch rate for #{from} to #{to} on #{date}: #{e.message}")
          nil
        end
      end.compact

      rates
    end
  end

  private

    def base_url
      "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1"
    end

    def client
      @client ||= Faraday.new do |faraday|
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
