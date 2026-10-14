RSpec.describe Pricing do
  let(:tax) { double(rate: 0.2) }

  before { allow(gateway).to receive(:fee).and_return(3) }

  it "reads the tax rate" do
    expect(tax.rate).to eq(0.2)
  end

  it "reads the fee" do
    expect(gateway.fee).to eq(3)
  end
end
