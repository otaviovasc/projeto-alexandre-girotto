require 'base64'
require 'json'
require 'net/http'
require 'uri'

module Fnrh
  class RealClient
    COMPLETED_PRECHECKIN_STATUSES = %w[
      PRECHECKIN_REALIZADO
      CHECKIN_REALIZADO
      CHECKOUT_REALIZADO
    ].freeze

    def initialize(filial)
      @filial = filial
    end

    def create_reservation(reserva)
      response = request_json(:post, '/reservas', body: reservation_payload(reserva, include_origin: true))
      reservation = response['reserva'] || response.dig('dados', 'reserva') || {}

      {
        reservation_id: reservation.fetch('reserva_id'),
        precheckin_url: reservation.fetch('link_precheckin'),
        status: 'awaiting_precheckin'
      }
    end

    def update_reservation(reserva)
      request_json(:put, "/reservas/#{reserva.fnrh_reservation_id}", body: reservation_payload(reserva))
      { success: true }
    end

    def check_in(reserva, at:)
      request_text(:post, "/reservas/#{reserva.fnrh_reservation_id}/checkin", body: timestamp(at))
      { success: true, occurred_at: at }
    end

    def check_out(reserva, at:)
      request_text(:post, "/reservas/#{reserva.fnrh_reservation_id}/checkout", body: timestamp(at))
      { success: true, occurred_at: at }
    end

    def no_show(reserva, at:)
      request_json(:post, "/reservas/#{reserva.fnrh_reservation_id}/noshow")
      { success: true, occurred_at: at }
    end

    def cancel(reserva, at:)
      request_json(:post, "/reservas/#{reserva.fnrh_reservation_id}/cancelar")
      { success: true, occurred_at: at }
    end

    def precheckin_status(reserva)
      response = request_json(:get, "/reservas/#{reserva.fnrh_reservation_id}/hospedes")
      statuses = Array(response['dados']).filter_map do |entry|
        entry.dig('hospede', 'situacao_hospede_id') || entry['situacao_hospede_id']
      end

      {
        completed: statuses.any? { |status| COMPLETED_PRECHECKIN_STATUSES.include?(status) },
        statuses: statuses
      }
    end

    private

    def reservation_payload(reserva, include_origin: false)
      payload = {
        numero_reserva: reservation_number(reserva),
        numero_reserva_ota: ota_number(reserva),
        data_entrada: reserva.start_date.iso8601,
        data_saida: reserva.end_date.iso8601,
        quantidade_hospede_adulto: reserva.fnrh_adults.presence || 1,
        quantidade_hospede_menor: reserva.fnrh_minors.presence || 0
      }
      payload[:origem_reserva_id] = reserva.imported? ? 'OTA' : 'MEIOHOSPEDAGEM' if include_origin
      payload
    end

    def reservation_number(reserva)
      "VG-#{reserva.id}"
    end

    def ota_number(reserva)
      return '' unless reserva.imported?

      [reserva.platform_uid, reserva.ical_uid_from_feed, reserva.ical_uid, reserva.origem]
        .find(&:present?).to_s.first(120)
    end

    def request_json(method, path, body: nil)
      request(method, path, body: body&.to_json, content_type: 'application/json')
    end

    def request_text(method, path, body:)
      request(method, path, body: body, content_type: 'text/plain')
    end

    def request(method, path, body:, content_type:)
      uri = URI("#{Configuration.base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'

      response = http.request(build_request(method, uri, body: body, content_type: content_type))
      return parse_response(response) if response.code.to_i.between?(200, 299)

      raise "FNRH #{response.code}: #{response.body.presence || 'sem detalhes'}"
    end

    def build_request(method, uri, body:, content_type:)
      request_class = {
        get: Net::HTTP::Get,
        post: Net::HTTP::Post,
        put: Net::HTTP::Put,
        delete: Net::HTTP::Delete,
        patch: Net::HTTP::Patch
      }.fetch(method)

      request = request_class.new(uri)
      request['Accept'] = 'application/json'
      request['Content-Type'] = content_type
      request['Authorization'] = "Basic #{encoded_credentials}"
      request.body = body if body
      request
    end

    def parse_response(response)
      return {} if response.body.blank?

      JSON.parse(response.body)
    rescue JSON::ParserError
      {}
    end

    def encoded_credentials
      username = Configuration.username_for(@filial)
      password = Configuration.password_for(@filial)
      raise 'Credenciais FNRH não configuradas para esta filial' if username.blank? || password.blank?

      Base64.strict_encode64("#{username}:#{password}")
    end

    def timestamp(value)
      value.in_time_zone.utc.iso8601(3)
    end
  end
end
