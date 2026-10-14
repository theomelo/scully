require "test_helper"

class UserTest < Minitest::Test
  def test_validates_email
    User.new(email: "x")
  end

  def test_broken
    x = (1 +
  end
end
