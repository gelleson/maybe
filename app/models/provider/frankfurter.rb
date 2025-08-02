class Provider::Frankfurter < Provider
  include ExchangeRateConcept

  # Subclass so errors caught in this provider are raised as Provider::Frankfurter::Error
  Error = Class.new(Provider::Error)
  InvalidExchangeRateError = Class.new(Error)

  def initialize
    # No API key required for Frankfurter API
  end

  def healthy?
    with_provider_response do
      response = client.get("#{base_url}/latest")
      JSON.parse(response.body).dig("rates").present?
    end
  end

  def usage
    # Frankfurter API doesn't provide usage data as it's free and unlimited
    # Return a mock usage data to maintain interface compatibility
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
      response = client.get("#{base_url}/#{date}") do |req|
        req.params["from"] = from
        req.params["to"] = to
      end

      data = JSON.parse(response.body)
      rate_value = data.dig("rates", to)

      raise InvalidExchangeRateError, "No rate found for #{from} to #{to} on #{date}" if rate_value.nil?

      Rate.new(date: date.to_date, from: from, to: to, rate: rate_value)
    end
  end

  def fetch_exchange_rates(from:, to:, start_date:, end_date:)
    with_provider_response do
      response = client.get("#{base_url}/#{start_date}..#{end_date}") do |req|
        req.params["from"] = from
        req.params["to"] = to
      end

      data = JSON.parse(response.body)
      rates_data = data.dig("rates")

      return [] if rates_data.nil?

      rates_data.map do |date_str, rate_data|
        rate_value = rate_data.dig(to)

        if date_str.nil? || rate_value.nil?
          Rails.logger.warn("#{self.class.name} returned invalid rate data for pair from: #{from} to: #{to} on: #{date_str}. Rate data: #{rate_value.inspect}")
          Sentry.capture_exception(InvalidExchangeRateError.new("#{self.class.name} returned invalid rate data"), level: :warning) do |scope|
            scope.set_context("rate", { from: from, to: to, date: date_str })
          end

          next
        end

        Rate.new(date: date_str.to_date, from: from, to: to, rate: rate_value)
      end.compact
    end
  end

  private

    def base_url
      "https://api.frankfurter.app"
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
