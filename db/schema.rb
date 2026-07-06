# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2026_07_06_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "cabanas", force: :cascade do |t|
    t.string "name"
    t.bigint "filial_id", null: false
    t.decimal "price"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "link_guia"
    t.string "color", default: "#000000"
    t.text "import_links"
    t.boolean "breakfast_included_airbnb", default: false, null: false
    t.boolean "breakfast_included_booking", default: false, null: false
    t.boolean "breakfast_included_holmy", default: false, null: false
    t.boolean "breakfast_included_direct", default: false, null: false
    t.index ["filial_id"], name: "index_cabanas_on_filial_id"
  end

  create_table "cart_items", force: :cascade do |t|
    t.bigint "cart_id", null: false
    t.bigint "item_id"
    t.bigint "service_id"
    t.bigint "reserva_id", null: false
    t.integer "quantity"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "payment_status"
    t.string "payment_link_id"
    t.string "payment_link_url"
    t.string "payment_order_code"
    t.datetime "payment_expires_at"
    t.decimal "unit_price_paid", precision: 10, scale: 2
    t.decimal "total_paid", precision: 10, scale: 2
    t.datetime "paid_at"
    t.date "service_date"
    t.text "observation"
    t.index ["cart_id"], name: "index_cart_items_on_cart_id"
    t.index ["item_id"], name: "index_cart_items_on_item_id"
    t.index ["payment_link_id"], name: "index_cart_items_on_payment_link_id"
    t.index ["payment_order_code"], name: "index_cart_items_on_payment_order_code"
    t.index ["reserva_id"], name: "index_cart_items_on_reserva_id"
    t.index ["service_id"], name: "index_cart_items_on_service_id"
  end

  create_table "carts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_carts_on_user_id"
  end

  create_table "filials", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "address"
    t.string "pagarme_api_key"
    t.string "pagarme_encryption_key"
    t.string "region"
  end

  create_table "fnrh_events", force: :cascade do |t|
    t.bigint "reserva_id", null: false
    t.string "event_type", null: false
    t.string "source", null: false
    t.string "status", null: false
    t.text "message"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reserva_id", "occurred_at"], name: "index_fnrh_events_on_reserva_id_and_occurred_at"
    t.index ["reserva_id"], name: "index_fnrh_events_on_reserva_id"
  end

  create_table "funil_mailers", force: :cascade do |t|
    t.string "fullname"
    t.string "number"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "holidays", force: :cascade do |t|
    t.string "name"
    t.date "date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "ical_reservation_changes", force: :cascade do |t|
    t.bigint "reserva_id", null: false
    t.string "platform", null: false
    t.string "old_uid"
    t.string "new_uid"
    t.date "old_start_date", null: false
    t.date "old_end_date", null: false
    t.date "new_start_date", null: false
    t.date "new_end_date", null: false
    t.datetime "acknowledged_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reserva_id", "acknowledged_at"], name: "index_ical_changes_on_reserva_and_acknowledged"
    t.index ["reserva_id"], name: "index_ical_reservation_changes_on_reserva_id"
  end

  create_table "info_da_cabanas", force: :cascade do |t|
    t.bigint "cabana_id", null: false
    t.string "info_type"
    t.string "title"
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cabana_id"], name: "index_info_da_cabanas_on_cabana_id"
  end

  create_table "items", force: :cascade do |t|
    t.string "name"
    t.integer "quantity"
    t.string "category"
    t.bigint "filial_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "critical_stock"
    t.boolean "show_in_marketplace"
    t.text "description"
    t.decimal "price"
    t.index ["filial_id"], name: "index_items_on_filial_id"
  end

  create_table "price_rules", force: :cascade do |t|
    t.bigint "cabana_id", null: false
    t.string "day_type"
    t.decimal "price"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cabana_id"], name: "index_price_rules_on_cabana_id"
  end

  create_table "promotions", force: :cascade do |t|
    t.bigint "cabana_id", null: false
    t.date "date"
    t.decimal "price"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "start_date"
    t.date "end_date"
    t.index ["cabana_id"], name: "index_promotions_on_cabana_id"
  end

  create_table "reserva_items", force: :cascade do |t|
    t.bigint "reserva_id", null: false
    t.bigint "item_id", null: false
    t.integer "quantity"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_reserva_items_on_item_id"
    t.index ["reserva_id"], name: "index_reserva_items_on_reserva_id"
  end

  create_table "reserva_services", force: :cascade do |t|
    t.bigint "reserva_id", null: false
    t.bigint "service_id", null: false
    t.integer "quantity"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "service_date"
    t.string "status", default: "active"
    t.text "observation"
    t.string "payment_status"
    t.string "payment_link_id"
    t.string "payment_link_url"
    t.string "payment_order_code"
    t.datetime "payment_expires_at"
    t.decimal "unit_price_paid", precision: 10, scale: 2
    t.decimal "total_paid", precision: 10, scale: 2
    t.datetime "paid_at"
    t.boolean "manual_date_override", default: false, null: false
    t.index ["payment_link_id"], name: "index_reserva_services_on_payment_link_id"
    t.index ["payment_order_code"], name: "index_reserva_services_on_payment_order_code"
    t.index ["reserva_id"], name: "index_reserva_services_on_reserva_id"
    t.index ["service_id"], name: "index_reserva_services_on_service_id"
  end

  create_table "reservas", force: :cascade do |t|
    t.date "start_date"
    t.date "end_date"
    t.boolean "early_checkin", default: false, null: false
    t.boolean "late_checkout", default: false, null: false
    t.bigint "cabana_id", null: false
    t.bigint "user_id", null: false
    t.decimal "total_price"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "payment_status"
    t.string "payment_link_id"
    t.string "payment_link_url"
    t.datetime "payment_expires_at"
    t.text "observation"
    t.string "origem"
    t.string "platform_uid"
    t.string "ical_uid"
    t.date "imported_start_date"
    t.date "imported_end_date"
    t.boolean "manual_override", default: false, null: false
    t.boolean "ical_uid_from_feed", default: false, null: false
    t.datetime "ical_missing_since"
    t.boolean "breakfast_manual_override", default: false, null: false
    t.boolean "group_created", default: false, null: false
    t.bigint "partnership_creator_id"
    t.datetime "ical_date_change_since"
    t.boolean "service_purchase_override", default: false, null: false
    t.integer "service_max_installments", default: 1, null: false
    t.string "fnrh_status", default: "not_eligible", null: false
    t.string "fnrh_reservation_id"
    t.text "fnrh_precheckin_url"
    t.integer "fnrh_adults", default: 1, null: false
    t.integer "fnrh_minors", default: 0, null: false
    t.datetime "fnrh_scheduled_checkin_at"
    t.datetime "fnrh_precheckin_at"
    t.datetime "fnrh_checkin_at"
    t.datetime "fnrh_checkout_at"
    t.datetime "fnrh_cancelled_at"
    t.datetime "fnrh_no_show_at"
    t.datetime "fnrh_synced_at"
    t.text "fnrh_last_error"
    t.string "guest_name"
    t.string "guest_phone"
    t.index ["cabana_id", "origem", "ical_uid"], name: "index_reservas_on_imported_ical"
    t.index ["cabana_id", "platform_uid"], name: "index_reservas_on_cabana_id_and_platform_uid"
    t.index ["cabana_id"], name: "index_reservas_on_cabana_id"
    t.index ["fnrh_reservation_id"], name: "index_reservas_on_fnrh_reservation_id", unique: true
    t.index ["fnrh_scheduled_checkin_at"], name: "index_reservas_on_fnrh_scheduled_checkin_at"
    t.index ["fnrh_status"], name: "index_reservas_on_fnrh_status"
    t.index ["ical_date_change_since"], name: "index_reservas_on_ical_date_change_since"
    t.index ["ical_missing_since"], name: "index_reservas_on_ical_missing_since"
    t.index ["partnership_creator_id"], name: "index_reservas_on_partnership_creator_id"
    t.index ["user_id"], name: "index_reservas_on_user_id"
  end

  create_table "services", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.decimal "price"
    t.string "duration"
    t.time "start_time"
    t.time "end_time"
    t.bigint "filial_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.boolean "show_in_marketplace"
    t.string "region", default: "SP"
    t.decimal "partner_price", null: false
    t.index ["filial_id"], name: "index_services_on_filial_id"
    t.index ["user_id"], name: "index_services_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role", default: 0
    t.bigint "filial_id"
    t.string "name"
    t.string "telephone"
    t.boolean "partner"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["filial_id"], name: "index_users_on_filial_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["telephone"], name: "index_users_on_telephone", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "cabanas", "filials"
  add_foreign_key "cart_items", "carts"
  add_foreign_key "cart_items", "items"
  add_foreign_key "cart_items", "reservas", on_delete: :cascade
  add_foreign_key "cart_items", "services"
  add_foreign_key "carts", "users"
  add_foreign_key "fnrh_events", "reservas"
  add_foreign_key "ical_reservation_changes", "reservas"
  add_foreign_key "info_da_cabanas", "cabanas"
  add_foreign_key "items", "filials"
  add_foreign_key "price_rules", "cabanas"
  add_foreign_key "promotions", "cabanas"
  add_foreign_key "reserva_items", "items"
  add_foreign_key "reserva_items", "reservas"
  add_foreign_key "reserva_services", "reservas"
  add_foreign_key "reserva_services", "services"
  add_foreign_key "reservas", "cabanas"
  add_foreign_key "reservas", "users"
  add_foreign_key "reservas", "users", column: "partnership_creator_id"
  add_foreign_key "services", "filials"
  add_foreign_key "services", "users"
  add_foreign_key "users", "filials"
end
