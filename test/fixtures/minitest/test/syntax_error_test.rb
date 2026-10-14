require "test_helper"

class CartTest < Minitest::Test
  def test_adds_an_item
    Cart.new.add(:book)
  end

  def test_totals_the_cart
    total = (Cart.new.total +
  end
end
