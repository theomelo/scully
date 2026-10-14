require "test_helper"

class CheckoutTest < Minitest::Test
  def test_calls_the_code_under_test
    gateway = Gateway.new
    gateway.stubs(:fee).returns(3)
    assert_equal 103, Checkout.new(gateway).total
  end

  def test_asserts_outside_the_stub_block
    gateway = Gateway.new
    gateway.stub(:fee, 3) do
      Checkout.new(gateway).pay
    end
    assert_equal 3, gateway.fee
  end

  def test_uses_a_mock_expectation
    mailer = Minitest::Mock.new
    mailer.expect(:deliver, true)
    assert_equal true, mailer.deliver
    mailer.verify
  end

  def test_uses_a_mocha_expectation
    mailer = Mailer.new
    mailer.expects(:deliver).returns(true)
    assert_equal true, mailer.deliver
  end

  def test_asserts_a_different_value
    cart = Cart.new
    cart.stubs(:total).returns(30)
    assert_equal 40, cart.total
  end
end
