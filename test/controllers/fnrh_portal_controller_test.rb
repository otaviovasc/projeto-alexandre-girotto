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

  test 'terms page records acceptance and continues to precheckin flow' do
    get fnrh_terms_path

    assert_response :success
    assert_select 'h1', 'Termos de hospedagem'

    assert_difference -> { @reserva.fnrh_events.where(event_type: 'terms_accepted').count }, 1 do
      post fnrh_terms_access_path, params: {
        terms_accepted: '1',
        guest_name: 'Maria',
        reservation_code: @reserva.id
      }
    end

    assert_redirected_to fnrh_portal_orientation_path
  end

  test 'terms page requires explicit acceptance' do
    assert_no_difference -> { @reserva.fnrh_events.where(event_type: 'terms_accepted').count } do
      post fnrh_terms_access_path, params: {
        guest_name: 'Maria',
        reservation_code: @reserva.id
      }
    end

    assert_redirected_to fnrh_terms_path
    assert_equal 'Confirme que leu e concorda com os termos para continuar.', flash[:alert]
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

  test 'releases information after admin bypasses precheckin' do
    Fnrh::TransitionService.new(@reserva, source: 'manual').bypass_precheckin

    post fnrh_portal_access_path, params: {
      guest_name: 'Maria',
      reservation_code: @reserva.id
    }

    assert_redirected_to fnrh_portal_information_path
    follow_redirect!
    assert_response :success
    assert_select 'h1', 'Informações da hospedagem'
    assert_equal 'precheckin_bypassed', @reserva.reload.fnrh_status
  end

  test 'ignores accents when matching the guest name' do
    @reserva.user.update!(name: 'Rômulo da Silva')

    post fnrh_portal_access_path, params: {
      guest_name: 'Romulo',
      reservation_code: @reserva.id
    }

    assert_redirected_to fnrh_portal_orientation_path
  end

  test 'releases a bypassed reservation even when it is no longer eligible for FNRH' do
    @reserva.update_column(:group_created, false)
    Fnrh::TransitionService.new(@reserva, source: 'manual').bypass_precheckin

    post fnrh_portal_access_path, params: {
      guest_name: 'Maria',
      reservation_code: @reserva.id
    }

    assert_redirected_to fnrh_portal_information_path
  end

  test 'releases partnership information without creating an FNRH reservation' do
    @reserva.user.update_column(:partner, true)
    @reserva.update_columns(
      group_created: false,
      fnrh_status: 'not_eligible',
      fnrh_reservation_id: nil,
      fnrh_precheckin_url: nil
    )

    post fnrh_portal_access_path, params: {
      guest_name: 'Maria',
      reservation_code: @reserva.id
    }

    assert_redirected_to fnrh_portal_information_path
    assert_nil @reserva.reload.fnrh_reservation_id
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
