require "test_helper"

class Api::AnalyticsControllerTest < ActionDispatch::IntegrationTest
  test "returns service purchase funnel metrics by unique reservation" do
    with_dashboard_token("secret-token") do
      GuestPortalEvent.create!(
        reserva: reservas(:one),
        event_name: GuestPortalEvent::OPENED_SERVICES_PAGE,
        occurred_at: Time.zone.parse("2026-09-10 10:00:00")
      )
      GuestPortalEvent.create!(
        reserva: reservas(:one),
        event_name: GuestPortalEvent::OPENED_SERVICES_PAGE,
        occurred_at: Time.zone.parse("2026-09-10 10:05:00")
      )
      GuestPortalEvent.create!(
        reserva: reservas(:one),
        event_name: GuestPortalEvent::ADDED_SERVICE_TO_CART,
        occurred_at: Time.zone.parse("2026-09-10 10:10:00")
      )
      GuestPortalEvent.create!(
        reserva: reservas(:two),
        event_name: GuestPortalEvent::OPENED_SERVICES_PAGE,
        occurred_at: Time.zone.parse("2026-09-10 11:00:00")
      )

      get "/api/analytics/service_purchase_funnel",
          params: { start_date: "2026-09-01", end_date: "2026-09-30" },
          headers: { "Authorization" => "Bearer secret-token" }
    end

    assert_response :success
    payload = response.parsed_body

    assert_equal true, payload.fetch("ok")
    assert_equal 2, payload.fetch("opened_services_page_unique_reservas")
    assert_equal 1, payload.fetch("added_service_to_cart_unique_reservas")
    assert_equal 3, payload.fetch("opened_services_page_events")
    assert_equal 1, payload.fetch("added_service_to_cart_events")
    assert_equal 50.0, payload.fetch("added_from_opened_rate")
  end

  test "requires dashboard token" do
    with_dashboard_token("secret-token") do
      get "/api/analytics/service_purchase_funnel"
    end

    assert_response :unauthorized
  end

  test "allows cors preflight without token" do
    with_dashboard_token("secret-token") do
      options "/api/analytics/service_purchase_funnel"
    end

    assert_response :success
  end

  private

  def with_dashboard_token(token)
    previous = ENV["DASHBOARD_API_TOKEN"]
    ENV["DASHBOARD_API_TOKEN"] = token
    yield
  ensure
    ENV["DASHBOARD_API_TOKEN"] = previous
  end
end
