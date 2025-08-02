require "test_helper"

class Provider::RegistryTest < ActiveSupport::TestCase
  test "fawaz currency api provider available" do
    provider = Provider::Registry.get_provider(:fawaz_currency_api)
    assert_instance_of Provider::FawazCurrencyApi, provider
  end

  test "frankfurter provider available" do
    provider = Provider::Registry.get_provider(:frankfurter)
    assert_instance_of Provider::Frankfurter, provider
  end

  test "exchange rate providers configured" do
    registry = Provider::Registry.for_concept(:exchange_rates)
    providers = registry.providers.compact
    assert providers.any?, "Should have at least one exchange rate provider"

    provider_classes = providers.map(&:class)
    assert_includes provider_classes, Provider::FawazCurrencyApi
    assert_includes provider_classes, Provider::Frankfurter
  end

  test "alpha vantage provider available" do
    provider = Provider::Registry.get_provider(:alpha_vantage)
    assert_instance_of Provider::AlphaVantage, provider
  end

  test "securities providers configured" do
    registry = Provider::Registry.for_concept(:securities)
    providers = registry.providers.compact
    assert providers.any?, "Should have at least one securities provider"

    provider_classes = providers.map(&:class)
    assert_includes provider_classes, Provider::AlphaVantage
  end

  test "synth provider not available" do
    assert_raises(Provider::Registry::Error) do
      Provider::Registry.get_provider(:synth)
    end
  end
end
