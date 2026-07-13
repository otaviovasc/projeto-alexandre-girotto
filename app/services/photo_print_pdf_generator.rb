# frozen_string_literal: true

require 'prawn'
require 'stringio'
require 'tempfile'

class PhotoPrintPdfGenerator
  PAGE_MARGIN = 36
  GAP = 18

  class Error < StandardError; end

  def initialize(record)
    @record = record
  end

  def call
    images = @record.photo_print_images.attachments.first(3)
    raise Error, 'Envie pelo menos uma foto para gerar o PDF.' if images.empty?

    @record.photo_print_pdf.purge if @record.photo_print_pdf.attached?
    @record.photo_print_pdf.attach(
      io: StringIO.new(render_pdf(images)),
      filename: pdf_filename,
      content_type: 'application/pdf'
    )

    @record.photo_print_pdf
  rescue Prawn::Errors::UnsupportedImageType => e
    raise Error, e.message
  end

  private

  def render_pdf(images)
    document = Prawn::Document.new(page_size: 'A4', margin: PAGE_MARGIN)
    boxes = layout_boxes(images.size, document.bounds)

    images.each_with_index do |attachment, index|
      draw_image(document, attachment, boxes[index])
    end

    document.render
  end

  def draw_image(document, attachment, box)
    with_image_file(attachment) do |file|
      image_width, image_height = image_size(file.path)
      scale = [box[:width] / image_width, box[:height] / image_height].min
      width = image_width * scale
      height = image_height * scale
      x = box[:x] + ((box[:width] - width) / 2.0)
      y = box[:y] - ((box[:height] - height) / 2.0)

      document.image file.path, at: [x, y], width: width, height: height
    end
  end

  def layout_boxes(count, bounds)
    case count
    when 1
      one_photo_layout(bounds)
    when 2
      two_photo_layout(bounds)
    else
      three_photo_layout(bounds)
    end
  end

  def one_photo_layout(bounds)
    width = [bounds.width * 0.68, 330].min
    height = [width * 1.5, bounds.height * 0.88].min
    [
      {
        x: (bounds.width - width) / 2.0,
        y: bounds.top - ((bounds.height - height) / 2.0),
        width: width,
        height: height
      }
    ]
  end

  def two_photo_layout(bounds)
    width = (bounds.width - GAP) / 2.0
    height = [width * 1.5, bounds.height * 0.88].min
    y = bounds.top - ((bounds.height - height) / 2.0)

    [
      { x: 0, y: y, width: width, height: height },
      { x: width + GAP, y: y, width: width, height: height }
    ]
  end

  def three_photo_layout(bounds)
    portrait_width = (bounds.width - GAP) / 2.0
    portrait_height = portrait_width * 1.5
    landscape_width = bounds.width
    landscape_height = landscape_width * (2.0 / 3.0)
    total_height = portrait_height + GAP + landscape_height
    top_y = bounds.top - [(bounds.height - total_height) / 2.0, 0].max

    [
      { x: 0, y: top_y, width: portrait_width, height: portrait_height },
      { x: portrait_width + GAP, y: top_y, width: portrait_width, height: portrait_height },
      { x: 0, y: top_y - portrait_height - GAP, width: landscape_width, height: landscape_height }
    ]
  end

  def with_image_file(attachment)
    extension = attachment.filename.extension_with_delimiter.to_s
    extension = '.jpg' if extension.empty?

    Tempfile.create(['photo-print', extension], binmode: true) do |file|
      file.write(attachment.blob.download)
      file.flush
      yield file
    end
  end

  def image_size(path)
    File.open(path, 'rb') do |file|
      signature = file.read(8)
      return png_size(file) if signature == "\x89PNG\r\n\x1A\n".b

      file.rewind
      return jpeg_size(file) if file.read(2) == "\xFF\xD8".b
    end

    raise Error, 'Formato de imagem inválido. Envie JPG ou PNG.'
  end

  def png_size(file)
    file.seek(16)
    file.read(8).unpack('NN')
  end

  def jpeg_size(file)
    loop do
      byte = file.read(1)
      raise Error, 'Imagem JPG inválida.' unless byte
      next unless byte == "\xFF".b

      marker = file.read(1)&.ord
      marker = file.read(1)&.ord while marker == 0xFF
      next if marker.nil? || marker == 0xD8 || marker == 0xD9

      length_data = file.read(2)
      raise Error, 'Imagem JPG inválida.' unless length_data&.bytesize == 2

      length = length_data.unpack1('n')
      if jpeg_size_marker?(marker)
        file.read(1)
        height = file.read(2).unpack1('n')
        width = file.read(2).unpack1('n')
        return [width, height]
      end

      file.seek(length - 2, IO::SEEK_CUR)
    end
  end

  def jpeg_size_marker?(marker)
    (0xC0..0xC3).cover?(marker) || (0xC5..0xC7).cover?(marker) ||
      (0xC9..0xCB).cover?(marker) || (0xCD..0xCF).cover?(marker)
  end

  def pdf_filename
    reserva_id = @record.respond_to?(:reserva_id) ? @record.reserva_id : @record.reserva&.id
    service_date = @record.respond_to?(:service_date) ? @record.service_date : nil
    date = service_date&.strftime('%Y-%m-%d')

    ['fotos-impressas', "reserva-#{reserva_id}", date].compact.join('-') + '.pdf'
  end
end
