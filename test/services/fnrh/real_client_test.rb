require 'test_helper'

module Fnrh
  class RealClientTest < ActiveSupport::TestCase
    setup do
      @filial = Filial.create!(name: 'Fattoria di Brauna', region: 'SP')
      @cabana = Cabana.create!(name: 'Zucchero - Teste Real', price: 100, filial: @filial)
      @user = User.create!(
        name: 'Hospede API',
        email: 'fnrh-real@example.com',
        password: 'password123'
      )
    end

    test 'creates reservation payload using FNRH API 2.4 fields' do
      reserva = create_reserva(origem: 'booking', platform_uid: 'BOOK-123')
      client = RealClient.new(@filial)
      captured = nil
      client.define_singleton_method(:request_json) do |method, path, body: nil|
        captured = { method: method, path: path, body: body }
        {
          'reserva' => {
            'reserva_id' => 'fnrh-123',
            'link_precheckin' => 'https://fnrh.example/precheckin/fnrh-123'
          }
        }
      end

      result = client.create_reservation(reserva)

      assert_equal 'fnrh-123', result[:reservation_id]
      assert_equal 'awaiting_precheckin', result[:status]

      assert_equal :post, captured[:method]
      assert_equal '/reservas', captured[:path]
      assert_equal "VG-#{reserva.id}", captured[:body][:numero_reserva]
      assert_equal 'BOOK-123', captured[:body][:numero_reserva_ota]
      assert_equal reserva.start_date.iso8601, captured[:body][:data_entrada]
      assert_equal reserva.end_date.iso8601, captured[:body][:data_saida]
      assert_equal 1, captured[:body][:quantidade_hospede_adulto]
      assert_equal 0, captured[:body][:quantidade_hospede_menor]
      assert_equal 'OTA', captured[:body][:origem_reserva_id]
    end

    test 'detects completed precheckin from reservation guests' do
      reserva = create_reserva
      reserva.update_columns(fnrh_reservation_id: 'fnrh-456')
      client = RealClient.new(@filial)
      captured = nil
      client.define_singleton_method(:request_json) do |method, path, body: nil|
        captured = { method: method, path: path, body: body }
        {
          'dados' => [
            {
              'hospede' => {
                'situacao_hospede_id' => 'PRECHECKIN_REALIZADO'
              }
            }
          ]
        }
      end

      result = client.precheckin_status(reserva)
      assert result[:completed]
      assert_equal ['PRECHECKIN_REALIZADO'], result[:statuses]
      assert_equal :get, captured[:method]
      assert_equal '/reservas/fnrh-456/hospedes', captured[:path]
    end

    private

    def create_reserva(origem: 'sistema', platform_uid: nil)
      Reserva.create!(
        cabana: @cabana,
        user: @user,
        start_date: Date.current + 15.days,
        end_date: Date.current + 17.days,
        payment_status: 'paid',
        group_created: true,
        total_price: 600,
        origem: origem,
        platform_uid: platform_uid
      )
    end
  end
end
