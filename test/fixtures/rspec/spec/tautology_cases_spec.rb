require "spec_helper"

RSpec.describe Checkout do
  let(:shop) { instance_double(Shop, name: "Corner", open?: true) }

  before { allow(gateway).to receive(:currency).and_return("EUR") }

  it "stubs in the body" do
    allow(cart).to receive(:total).and_return(30)
    expect(cart.total).to eq(30)
  end

  it "stubs several messages at once" do
    allow(cart).to receive_messages(count: 2, empty?: false)
    expect(cart.count).to eql(2)
  end

  it "reads a let double's attribute" do
    expect(shop.name).to eq("Corner")
  end

  it "reads a local double's attribute" do
    coupon = double("coupon", percent: 10)
    expect(coupon.percent).to equal(10)
  end

  context "when nested" do
    it "sees the outer before" do
      expect(gateway.currency).to eq("EUR")
    end
  end

  subject { gateway.currency }

  it { is_expected.to eq("EUR") }
end
