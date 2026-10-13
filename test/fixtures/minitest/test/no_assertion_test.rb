require "test_helper"

class OrderTest < Minitest::Test
  def test_total
    Order.new.total
  end

  def test_stubs_but_checks_nothing
    gateway = Object.new
    gateway.stubs(:charge).returns(true)
    Order.new.pay(gateway)
  end
end

class InvoiceTest < ActiveSupport::TestCase
  test "totals the order" do
    build_invoice.total
  end
end

describe Order do
  it "ships" do
    Order.new.ship
  end
end
