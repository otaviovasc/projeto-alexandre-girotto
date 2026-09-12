class AddSourceChannelToReservas < ActiveRecord::Migration[7.0]
  def up
    add_column :reservas, :source_channel, :string
    add_index :reservas, :source_channel

    execute <<~SQL.squish
      UPDATE reservas
      SET source_channel = CASE
        WHEN partnership_creator_id IS NOT NULL
          OR LOWER(COALESCE(observation, '')) LIKE '%parceria%'
          THEN 'parceria'
        WHEN LOWER(COALESCE(origem, '')) IN ('airbnb', 'booking', 'holmy')
          THEN LOWER(origem)
        WHEN EXISTS (
          SELECT 1
          FROM reserva_payments
          WHERE reserva_payments.reserva_id = reservas.id
            AND reserva_payments.public_booking_payload ->> 'source' = 'public_booking'
        )
          THEN 'site_oficial'
        WHEN LOWER(COALESCE(origem, '')) = 'sistema'
          OR origem IS NULL
          OR origem = ''
          THEN 'whatsapp'
        ELSE 'outro'
      END
      WHERE source_channel IS NULL
    SQL
  end

  def down
    remove_index :reservas, :source_channel
    remove_column :reservas, :source_channel
  end
end
