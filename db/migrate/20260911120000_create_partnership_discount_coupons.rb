class CreatePartnershipDiscountCoupons < ActiveRecord::Migration[7.0]
  def change
    create_table :partnership_discount_coupons do |t|
      t.string :code, null: false
      t.string :normalized_code, null: false
      t.decimal :discount_percent, precision: 5, scale: 2, null: false
      t.boolean :active, default: true, null: false
      t.references :created_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :partnership_discount_coupons, :normalized_code, unique: true

    add_reference :reservas, :partnership_discount_coupon, foreign_key: true
    add_column :reservas, :discount_coupon_code, :string
    add_column :reservas, :discount_percent, :decimal, precision: 5, scale: 2
    add_column :reservas, :discount_amount, :decimal, precision: 10, scale: 2, default: 0, null: false
  end
end
