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

ActiveRecord::Schema[7.0].define(version: 2024_09_11_122233) do
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
    t.index ["filial_id"], name: "index_cabanas_on_filial_id"
  end

  create_table "filials", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "address"
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

  create_table "reserva_services", force: :cascade do |t|
    t.bigint "reserva_id", null: false
    t.bigint "service_id", null: false
    t.integer "quantity"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reserva_id"], name: "index_reserva_services_on_reserva_id"
    t.index ["service_id"], name: "index_reserva_services_on_service_id"
  end

  create_table "reservas", force: :cascade do |t|
    t.date "start_date"
    t.date "end_date"
    t.bigint "cabana_id", null: false
    t.bigint "user_id", null: false
    t.decimal "total_price"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cabana_id"], name: "index_reservas_on_cabana_id"
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
    t.index ["filial_id"], name: "index_services_on_filial_id"
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["filial_id"], name: "index_users_on_filial_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "cabanas", "filials"
  add_foreign_key "info_da_cabanas", "cabanas"
  add_foreign_key "items", "filials"
  add_foreign_key "price_rules", "cabanas"
  add_foreign_key "reserva_services", "reservas"
  add_foreign_key "reserva_services", "services"
  add_foreign_key "reservas", "cabanas"
  add_foreign_key "reservas", "users"
  add_foreign_key "services", "filials"
  add_foreign_key "users", "filials"
end
