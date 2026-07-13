# frozen_string_literal: true

class PhotoPrintAttachmentCleanup
  def self.run(cutoff_date: 2.days.ago.to_date)
    new(cutoff_date: cutoff_date).run
  end

  def initialize(cutoff_date:)
    @cutoff_date = cutoff_date
  end

  def run
    purge_records(ReservaService.joins(:reserva).where(reservas: { end_date: ..@cutoff_date }))
    purge_records(CartItem.joins(:reserva).where(reservas: { end_date: ..@cutoff_date }))
  end

  private

  def purge_records(scope)
    scope.find_each do |record|
      record.photo_print_images.purge_later if record.photo_print_images.attached?
      record.photo_print_pdf.purge_later if record.photo_print_pdf.attached?
    end
  end
end
