require "test_helper"

class OrderTest < Minitest::Test
  def setup
    @order = Order.new(items: [Item.new(price: 2), Item.new(price: 1)])
  end

  def test_total
    assert_equal 3, @order.total
  end

  def test_rejects_an_empty_order
    assert_raises(Order::Empty) { Order.new(items: []).save! }
  end

  def test_charges_the_gateway
    gateway = mock("gateway")
    gateway.expects(:charge).with(3)
    @order.pay(gateway)
  end

  def test_notifies_the_mailer
    mailer = Minitest::Mock.new
    mailer.expect(:deliver, true, [@order])
    @order.notify(mailer)
    mailer.verify
  end

  def test_checks_through_an_assert_helper
    assert_shipped @order
  end

  private

  def assert_shipped(order)
    assert_predicate order, :shipped?
  end
end

class InvoiceTest < ActiveSupport::TestCase
  test "totals the order" do
    assert_equal 3, Invoice.new(Order.new).total
  end
end

describe Order do
  it "must total" do
    _(Order.new.total).must_equal 0
  end

  it "wont be paid" do
    Order.new.paid?.wont_equal true
  end
end
