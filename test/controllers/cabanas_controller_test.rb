require "test_helper"

class CabanasControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get cabanas_index_url
    assert_response :success
  end

  test "should get show" do
    get cabanas_show_url
    assert_response :success
  end
end
