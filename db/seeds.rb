# db/seeds.rb

# # Create filials
# filial1 = Filial.create!(name: 'Serra da Mantiqueira')
# filial2 = Filial.create!(name: 'Fattoria di Brauna')

# # Create an admin user
# admin = User.create!(
#   email: 'villaggiogirotto@gmail.com',
#   password: 'Aleserver10!',
#   password_confirmation: 'Aleserver10!',
#   role: :admin
# )
# puts "Admin created: #{admin.email}"

# # Create manager users
# manager1 = User.create!(
#   email: 'estoque@villaggio.com',
#   password: 'Estoque10!',
#   password_confirmation: 'Estoque10!',
#   role: :manager,
#   filial: filial1
# )
# puts "Manager created: #{manager1.email}"

# manager2 = User.create!(
#   email: 'estoque2@gmail.com',
#   password: 'Estoque10!',
#   password_confirmation: 'Estoque10!',
#   role: :manager,
#   filial: filial2
# )
# puts "Manager created: #{manager2.email}"


mercadomg = Filial.create!(name: 'Mercadinho MG')
mercadosp = Filial.create!(name: 'Mercadinho SP')

manager3 = User.create!(
  email: 'estoque3@gmail.com',
  password: 'Estoque10!',
  password_confirmation: 'Estoque10!',
  role: :manager,
  filial: mercadomg
)

manager4 = User.create!(
  email: 'estoque4@gmail.com',
  password: 'Estoque10!',
  password_confirmation: 'Estoque10!',
  role: :manager,
  filial: mercadosp
)
