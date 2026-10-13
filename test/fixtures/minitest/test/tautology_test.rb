require "test_helper"

class PricingTest < Minitest::Test
  def setup
    @tax = Tax.new
    @tax.stubs(:rate).returns(0.2)
  end

  def test_reads_the_setup_stub
    assert_equal 0.2, @tax.rate
  end

  def test_reads_a_block_stub
    gateway = Gateway.new
    gateway.stub(:fee, 3) do
      assert_equal 3, gateway.fee
    end
  end

  def test_reads_a_mocha_stub
    cart = Cart.new
    cart.stubs(:total).returns(30)
    assert_equal 30, cart.total
  end
end

describe Checkout do
  let(:shop) { Shop.new }
  before { shop.stubs(:currency).returns("EUR") }

  it "reads the before stub" do
    _(shop.currency).must_equal "EUR"
  end
end
