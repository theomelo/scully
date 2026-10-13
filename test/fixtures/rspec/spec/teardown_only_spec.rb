require "spec_helper"

RSpec.describe Order do
  let(:order) { Order.new }

  after { expect(order).to be_valid }

  it "only checks in teardown" do
    order.add(Item.new(price: 2))
  end
end
