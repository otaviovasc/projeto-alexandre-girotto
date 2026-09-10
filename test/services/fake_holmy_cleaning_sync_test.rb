require 'test_helper'

class FakeHolmyCleaningSyncTest < ActiveSupport::TestCase
  setup do
    OperationalServiceOccurrence.delete_all
    ReservaService.delete_all
    Reserva.delete_all
    Service.delete_all
    Cabana.delete_all
    Filial.delete_all
    User.delete_all

    @serra = Filial.create!(name: 'Serra da Mantiqueira')
    @brauna = Filial.create!(name: 'Fattoria di Brauna')
    @user = User.create!(name: 'Teste', email: 'teste-fake-holmy@example.com', password: 'password')
    @nuvolo = Cabana.create!(name: 'Nuvolo - Serra da Mantiqueira', filial: @serra, price: 799)
    @vita = Cabana.create!(name: 'Vita - Serra da Mantiqueira', filial: @serra, price: 1199)
    @entrada_mg = Service.create!(
      name: '➡️ Limpeza Entrada (MG)',
      filial: @serra,
      user: @user,
      price: 0,
      partner_price: 0
    )
  end

  test 'creates fake holmy cleaning after five empty days and skips vita' do
    travel_to Time.zone.local(2026, 9, 10, 8, 0) do
      add_real_cleaning_on(Date.new(2026, 9, 9))

      result = FakeHolmyCleaningSync.run(start_date: Date.new(2026, 9, 10), end_date: Date.new(2026, 9, 20))

      assert_equal 2, result.created
      assert OperationalServiceOccurrence.exists?(
        cabana: @nuvolo,
        name: FakeHolmyCleaningSync::ENTRY_NAME,
        service_date: Date.new(2026, 9, 14),
        status: 'active'
      )
      assert OperationalServiceOccurrence.exists?(
        cabana: @nuvolo,
        name: FakeHolmyCleaningSync::EXIT_NAME,
        service_date: Date.new(2026, 9, 16),
        status: 'active'
      )
      assert_empty OperationalServiceOccurrence.where(cabana: @vita)
    end
  end

  test 'moves fake cleaning one day earlier when next real cleaning would collide' do
    travel_to Time.zone.local(2026, 9, 10, 8, 0) do
      add_real_cleaning_on(Date.new(2026, 9, 9))
      add_real_cleaning_on(Date.new(2026, 9, 16))

      FakeHolmyCleaningSync.run(start_date: Date.new(2026, 9, 10), end_date: Date.new(2026, 9, 20))

      assert OperationalServiceOccurrence.exists?(
        cabana: @nuvolo,
        name: FakeHolmyCleaningSync::ENTRY_NAME,
        service_date: Date.new(2026, 9, 13),
        status: 'active'
      )
      assert OperationalServiceOccurrence.exists?(
        cabana: @nuvolo,
        name: FakeHolmyCleaningSync::EXIT_NAME,
        service_date: Date.new(2026, 9, 15),
        status: 'active'
      )
    end
  end

  test 'cancels obsolete fake cleaning with stable id when a real cleaning appears' do
    travel_to Time.zone.local(2026, 9, 10, 8, 0) do
      add_real_cleaning_on(Date.new(2026, 9, 9))
      FakeHolmyCleaningSync.run(start_date: Date.new(2026, 9, 10), end_date: Date.new(2026, 9, 20))
      old_entry = OperationalServiceOccurrence.find_by!(
        cabana: @nuvolo,
        event_type: FakeHolmyCleaningSync::ENTRY_TYPE,
        service_date: Date.new(2026, 9, 14)
      )

      add_real_cleaning_on(Date.new(2026, 9, 16))

      result = FakeHolmyCleaningSync.run(start_date: Date.new(2026, 9, 10), end_date: Date.new(2026, 9, 20))

      assert_operator result.cancelled, :>=, 1
      assert old_entry.reload.cancelled?
      assert_equal old_entry.stable_id, OperationalServiceOccurrence.find(old_entry.id).stable_id
    end
  end

  private

  def add_real_cleaning_on(date)
    @cleaning_anchor_counter ||= 0
    anchor_start = Date.new(2026, 12, 10) + @cleaning_anchor_counter.days
    @cleaning_anchor_counter += 3

    reserva = Reserva.create!(
      cabana: @nuvolo,
      user: @user,
      start_date: anchor_start,
      end_date: anchor_start + 1.day,
      payment_status: 'paid',
      blocks_availability: true,
      total_price: 1000
    )
    reserva.reserva_services.create!(
      service: @entrada_mg,
      service_date: date,
      quantity: 1
    )
  end
end
