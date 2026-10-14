module CartHelpers
  def build_cart(*items)
    Cart.new.tap { |cart| items.each { |item| cart.add(item) } }
  end
end
