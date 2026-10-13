require "test_helper"

class OrderTest < Minitest::Test
  def test_skipped
    skip "flaky on CI"
    Order.new.total
  end
end

class InvoiceTest < ActiveSupport::TestCase
  test "is skipped" do
    skip
    Invoice.new.total
  end

  test "is not written yet"
end

describe Order do
  it "has no body yet"

  it "is skipped" do
    skip "later"
    Order.new.ship
  end
end
