require "spec_helper"

RSpec.describe Order do
  subject(:order) { Order.new(items: [Item.new(price: 2), Item.new(price: 1)]) }

  def expect_total(order, amount)
    expect(order.total).to eq(amount)
  end

  def check_paid(order)
    expect_total(order, 3)
  end

  it "sums line items" do
    expect(order.total).to eq(3)
  end

  it "rejects an empty order" do
    expect { Order.new(items: []).save! }.to raise_error(Order::Empty)
  end

  it { is_expected.to be_valid }

  it "supports the should syntax" do
    order.total.should == 3
  end

  it "notifies the mailer" do
    mailer = double("mailer")
    expect(mailer).to receive(:deliver).with(order)
    order.notify(mailer)
  end

  it "checks through a helper in this file" do
    check_paid(order)
  end

  it "checks through an expect_ helper" do
    expect_shipped(order)
  end
end
