require "spec_helper"

RSpec.describe Order do
  xit "is skipped with xit" do
    Order.new.total
  end

  it "is skipped with metadata", :skip do
    Order.new.total
  end

  it "calls pending" do
    pending "not built yet"
    Order.new.total
  end

  it "calls skip" do
    skip "flaky on CI"
    Order.new.total
  end

  pending "is declared pending" do
    Order.new.total
  end

  it "has no body yet"

  xdescribe "a skipped group" do
    it "is skipped with its group" do
      Order.new.total
    end
  end
end
