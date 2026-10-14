require "spec_helper"

RSpec.describe Checkout do
  let(:tax) { double(rate: 0.2) }

  it "calls the code under test" do
    allow(gateway).to receive(:fee).and_return(3)
    expect(Checkout.new(gateway).total).to eq(103)
  end

  it "asserts on a different method" do
    allow(gateway).to receive(:fee).and_return(3)
    expect(gateway.currency).to eq(3)
  end

  it "asserts on a different receiver" do
    allow(gateway).to receive(:fee).and_return(3)
    expect(other_gateway.fee).to eq(3)
  end

  it "asserts on a different value" do
    expect(tax.rate).to eq(0.5)
  end

  it "stubs after the assertion" do
    expect(cart.total).to eq(30)
    allow(cart).to receive(:total).and_return(30)
  end

  it "uses a message expectation" do
    expect(mailer).to receive(:deliver).and_return(true)
    expect(mailer.deliver).to eq(true)
  end

  it "replaces the stub before asserting" do
    allow(cart).to receive(:total).and_return(30)
    allow(cart).to receive(:total).and_return(40)
    expect(cart.total).to eq(30)
  end
end
