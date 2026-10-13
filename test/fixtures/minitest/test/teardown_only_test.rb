require "test_helper"

class OrderTest < Minitest::Test
  def setup
    @order = Order.new
  end

  def teardown
    assert_predicate @order, :valid?
  end

  def test_only_checks_in_teardown
    @order.add(Item.new(price: 2))
  end
end
