require "spec_helper"

RSpec.shared_examples "a priced thing" do
  it "has a price" do
    expect(subject.price).to be_positive
  end

  it "rounds the price" do
    subject.price.round
  end
end

RSpec.describe Item do
  subject { Item.new(price: 2) }

  it_behaves_like "a priced thing"
end
