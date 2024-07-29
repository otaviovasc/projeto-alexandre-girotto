# db/seeds.rb

# Clear existing data
User.destroy_all
Filial.destroy_all
Item.destroy_all

# Create filials
filial1 = Filial.create!(name: 'Filial 1')
filial2 = Filial.create!(name: 'Filial 2')

# Create Items
Item.create(name: "Detergente", quantity: 10, category: 'Limpeza', filial: filial1)
Item.create(name: "Soap Powder", quantity: 2, category: 'Limpeza', filial: filial2)
Item.create(name: "Rice Bag", quantity: 4, category: 'Comida', filial: filial1)

# Create an admin user
admin = User.create!(
  email: 'admin@example.com',
  password: 'password',
  password_confirmation: 'password',
  role: :admin
)
puts "Admin created: #{admin.email}"

# Create manager users
manager1 = User.create!(
  email: 'manager1@example.com',
  password: 'password',
  password_confirmation: 'password',
  role: :manager,
  filial: filial1
)
puts "Manager created: #{manager1.email}"

manager2 = User.create!(
  email: 'manager2@example.com',
  password: 'password',
  password_confirmation: 'password',
  role: :manager,
  filial: filial2
)
puts "Manager created: #{manager2.email}"

manager3 = User.create!(
  email: 'manager3@example.com',
  password: 'password',
  password_confirmation: 'password',
  role: :manager,
  filial: filial1
)
puts "Manager created: #{manager3.email}"
