# db/seeds.rb

# Clear existing data
User.destroy_all
Filial.destroy_all
Item.destroy_all

# Create filials
filial1 = Filial.create!(name: 'Serra da Mantiqueira')
filial2 = Filial.create!(name: 'Fattoria di Brauna')

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
  email: 'estoque@villaggio.com',
  password: 'Estoque10!',
  password_confirmation: 'Estoque10!',
  role: :manager,
  filial: filial1
)
puts "Manager created: #{manager1.email}"

manager2 = User.create!(
  email: 'estoque2@gmail.com',
  password: 'Estoque10!',
  password_confirmation: 'Estoque10!',
  role: :manager,
  filial: filial2
)
puts "Manager created: #{manager2.email}"
