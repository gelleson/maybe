require "test_helper"
require "ostruct"

class Provider::FrankfurterTest < ActiveSupport::TestCase
  include ExchangeRateProviderInterfaceTest

  setup do
    @subject = @frankfurter = Provider::Frankfurter.new
  end

  test "health check" do
    VCR.use_cassette("frankfurter/health") do
      assert @frankfurter.healthy?
    end
  end

  test "usage info" do
    response = @frankfurter.usage
    assert response.success?
    usage = response.data
    assert_equal 0, usage.used
    assert_equal Float::INFINITY, usage.limit
    assert_equal 0.0, usage.utilization
    assert_equal "free", usage.plan
  end
end