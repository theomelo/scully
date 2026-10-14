require "spec_helper"

RSpec.describe Order do
  let(:order) { Order.new }

  it "sums line items" do
    order.total
  end

  describe "#ship" do
    def prepare(order)
      order.pack
    end

    context "when paid" do
      it "ships the order" do
        prepare(order)
        order.ship
      end
    end
  end

  specify do
    allow(order).to receive(:paid?).and_return(true)
    order.ship
  end

  it "reads the page without asserting" do
    page.has_content?("Shipped")
  end
end
