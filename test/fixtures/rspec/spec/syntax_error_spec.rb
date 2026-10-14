require "spec_helper"

RSpec.describe Cart do
  it "adds an item" do
    Cart.new.add(:book)
  end

  it "totals the cart" do
    total = (Cart.new.total +
  end
end
