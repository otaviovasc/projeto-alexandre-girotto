require "test_helper"

class Admin::InfoDaCabanasControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get admin_info_da_cabanas_index_url
    assert_response :success
  end

  test "should get new" do
    get admin_info_da_cabanas_new_url
    assert_response :success
  end

  test "should get create" do
    get admin_info_da_cabanas_create_url
    assert_response :success
  end

  test "should get edit" do
    get admin_info_da_cabanas_edit_url
    assert_response :success
  end

  test "should get update" do
    get admin_info_da_cabanas_update_url
    assert_response :success
  end

  test "should get destroy" do
    get admin_info_da_cabanas_destroy_url
    assert_response :success
  end
end
