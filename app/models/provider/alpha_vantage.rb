class Provider::AlphaVantage < Provider
  include SecurityConcept

  # Subclass so errors caught in this provider are raised as Provider::AlphaVantage::Error
  Error = Class.new(Provider::Error)
  InvalidSecurityError = Class.new(Error)

  API_BASE_URL = "https://www.alphavantage.co/query"

  def initialize(api_key = nil)
    @api_key = api_key || ENV["ALPHA_VANTAGE_API_KEY"] || "demo"
  end

  def healthy?
    with_provider_response do
      response = client.get("?function=GLOBAL_QUOTE&symbol=AAPL&apikey=#{@api_key}")
      !JSON.parse(response.body).key?("Error Message")
    end
  end

  def usage
    # Alpha Vantage doesn't provide usage endpoint, return basic info
    UsageData.new(
      used: 0,
      limit: @api_key == "demo" ? 25 : 500, # Demo has 25/day, free tier has 500/day
      utilization: 0.0,
      plan: @api_key == "demo" ? "demo" : "free"
    )
  end

  def search_securities(symbol, country_code: nil, exchange_operating_mic: nil)
    with_provider_response do
      # Alpha Vantage doesn't have a dedicated search endpoint
      # We'll use the SYMBOL_SEARCH function which searches for companies
      response = client.get("?function=SYMBOL_SEARCH&keywords=#{symbol}&apikey=#{@api_key}")
      data = JSON.parse(response.body)

      if data["bestMatches"]
        securities = data["bestMatches"].map do |match|
          Security.new(
            symbol: match["1. symbol"],
            name: match["2. name"],
            logo_url: nil, # Alpha Vantage doesn't provide logos in search
            exchange_operating_mic: map_region_to_mic(match["4. region"]),
            country_code: map_region_to_country(match["4. region"])
          )
        end
        securities
      else
        []
      end
    end
  end

  def fetch_security_info(symbol:, exchange_operating_mic:)
    with_provider_response do
      # Use OVERVIEW function to get company information
      response = client.get("?function=OVERVIEW&symbol=#{symbol}&apikey=#{@api_key}")
      data = JSON.parse(response.body)

      if data["Symbol"] && !data.key?("Error Message")
        SecurityInfo.new(
          symbol: data["Symbol"],
          name: data["Name"],
          links: {},
          logo_url: nil,
          description: data["Description"],
          kind: data["AssetType"],
          exchange_operating_mic: exchange_operating_mic
        )
      else
        raise Error.new("Security info not found for #{symbol}")
      end
    end
  end

  def fetch_security_price(symbol:, exchange_operating_mic:, date:)
    with_provider_response do
      if date == Date.current
        # Use GLOBAL_QUOTE for current day
        response = client.get("?function=GLOBAL_QUOTE&symbol=#{symbol}&apikey=#{@api_key}")
        data = JSON.parse(response.body)
        quote = data["Global Quote"]

        if quote && quote["05. price"]
          Price.new(
            symbol: symbol,
            date: Date.parse(quote["07. latest trading day"]),
            price: quote["05. price"].to_f,
            currency: "USD", # Alpha Vantage primarily provides USD prices
            exchange_operating_mic: exchange_operating_mic
          )
        else
          raise Error.new("Price not found for #{symbol}")
        end
      else
        # For historical dates, we need to use TIME_SERIES_DAILY
        fetch_security_prices(symbol: symbol, exchange_operating_mic: exchange_operating_mic, start_date: date, end_date: date).first
      end
    end
  end

  def fetch_security_prices(symbol:, exchange_operating_mic:, start_date:, end_date:)
    with_provider_response do
      # Use TIME_SERIES_DAILY for historical prices
      response = client.get("?function=TIME_SERIES_DAILY&symbol=#{symbol}&apikey=#{@api_key}&outputsize=full")
      data = JSON.parse(response.body)
      time_series = data["Time Series (Daily)"]

      if time_series
        prices = []
        time_series.each do |date_str, price_data|
          price_date = Date.parse(date_str)

          # Filter by date range
          if price_date >= start_date && price_date <= end_date
            prices << Price.new(
              symbol: symbol,
              date: price_date,
              price: price_data["4. close"].to_f,
              currency: "USD",
              exchange_operating_mic: exchange_operating_mic
            )
          end
        end

        prices.sort_by(&:date)
      else
        error_msg = data["Error Message"] || data["Information"] || "Unknown error"
        raise Error.new("Failed to fetch prices: #{error_msg}")
      end
    end
  end

  private

    def map_region_to_mic(region)
      case region&.upcase
      when "UNITED STATES"
        "XNAS" # Default to NASDAQ
      when "UNITED KINGDOM"
        "XLON"
      when "CANADA"
        "XTSE"
      else
        nil
      end
    end

    def map_region_to_country(region)
      case region&.upcase
      when "UNITED STATES"
        "US"
      when "UNITED KINGDOM"
        "GB"
      when "CANADA"
        "CA"
      else
        nil
      end
    end

    def client
      @client ||= Faraday.new(url: API_BASE_URL) do |faraday|
        faraday.request(:retry, {
          max: 2,
          interval: 0.05,
          interval_randomness: 0.5,
          backoff_factor: 2
        })
        faraday.response(:raise_error)
      end
    end
end
