require "test_helper"

class Admin::FunilMailersControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get admin_funil_mailers_index_url
    assert_response :success
  end
end
