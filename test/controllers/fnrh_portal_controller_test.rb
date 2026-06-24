require 'test_helper'

class FnrhPortalControllerTest < ActionDispatch::IntegrationTest
  setup do
    filial = Filial.create!(name: 'Serra da Mantiqueira', region: 'MG')
    cabana = Cabana.create!(name: 'Nuvolo - Teste Portal', price: 100, filial: filial)
    user = User.create!(
      name: 'Maria da Silva',
      email: 'maria-fnrh@example.com',
      password: 'password123'
    )
    @reserva = Reserva.create!(
      cabana: cabana,
      user: user,
      start_date: Date.current + 10.days,
      end_date: Date.current + 12.days,
      payment_status: 'paid',
      group_created: true,
      total_price: 900
    )
    Fnrh::ReservationSyncService.new(@reserva).call(force: true)
  end

  test 'identifies reservation and shows orientation before opening precheckin link' do
    post fnrh_portal_access_path, params: {
      guest_name: 'Maria',
      reservation_code: @reserva.id
    }

    assert_redirected_to fnrh_portal_orientation_path
    follow_redirect!
    assert_select 'h1', 'Pré-check-in gov.br'
    assert_select 'form button', 'Entrar pelo gov.br'
  end

  test 'opens stored precheckin link after orientation' do
    post fnrh_portal_access_path, params: {
      guest_name: 'Maria',
      reservation_code: @reserva.id
    }

    post fnrh_portal_start_precheckin_path

    assert_redirected_to @reserva.reload.fnrh_precheckin_url
  end

  test 'releases information after mock precheckin is completed' do
    post fnrh_portal_access_path, params: {
      guest_name: 'Maria',
      reservation_code: @reserva.id
    }
    post fnrh_portal_start_precheckin_path
    post fnrh_mock_complete_precheckin_path(@reserva.fnrh_reservation_id)
    follow_redirect!

    assert_response :success
    assert_select 'h1', 'Informações da hospedagem'
    assert_equal 'precheckin_completed', @reserva.reload.fnrh_status
  end

  test 'shows waiting page when guest returns before precheckin confirmation' do
    post fnrh_portal_access_path, params: {
      guest_name: 'Maria',
      reservation_code: @reserva.id
    }

    post fnrh_portal_access_path, params: {
      guest_name: 'Maria',
      reservation_code: @reserva.id
    }

    assert_redirected_to fnrh_portal_waiting_path
    follow_redirect!
    assert_select 'h1', 'Pré-check-in em análise'
  end

  test 'does not release a reservation that is not ready' do
    @reserva.update_columns(group_created: false, fnrh_reservation_id: nil, fnrh_precheckin_url: nil)

    post fnrh_portal_access_path, params: {
      guest_name: 'Maria',
      reservation_code: @reserva.id
    }

    assert_redirected_to fnrh_portal_path
    assert_equal 'Seu acesso ao pré-check-in ainda está sendo preparado. Tente novamente em alguns minutos.', flash[:alert]
  end

  test 'does not reopen a cancelled reservation through its old precheckin link' do
    Fnrh::TransitionService.new(@reserva).cancel

    post fnrh_mock_complete_precheckin_path(@reserva.fnrh_reservation_id)

    assert_redirected_to fnrh_mock_precheckin_path(@reserva.fnrh_reservation_id)
    assert_equal 'cancelled', @reserva.reload.fnrh_status
  end
end
