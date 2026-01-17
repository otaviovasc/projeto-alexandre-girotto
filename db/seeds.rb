# db/seeds.rb

# Limpar dados existentes (descomente se quiser resetar tudo)
# Cart.destroy_all
# Service.destroy_all
# Reserva.destroy_all
# Cabana.destroy_all
# User.destroy_all
# Filial.destroy_all

# Criar filiais
filial1 = Filial.find_or_create_by!(name: 'Serra da Mantiqueira')
filial2 = Filial.find_or_create_by!(name: 'Fattoria di Brauna')
puts "Filiais criadas: #{filial1.name}, #{filial2.name}"

# Criar usuário admin de teste (fácil de lembrar)
admin = User.find_or_initialize_by(email: 'admin@teste.com')
admin.update!(
  name: 'Admin Teste',
  password: '123456',
  password_confirmation: '123456',
  role: :admin
)
puts "Admin criado: #{admin.email} / senha: 123456"

# Criar usuário manager de teste
manager = User.find_or_initialize_by(email: 'manager@teste.com')
manager.update!(
  name: 'Manager Teste',
  password: '123456',
  password_confirmation: '123456',
  role: :manager,
  filial: filial1
)
puts "Manager criado: #{manager.email} / senha: 123456"
# 10.times do |i|
#   Item.create!(
#     name: "Item #{i + 1}",
#     quantity: rand(1..100),
#     category: "Limpeza e Higiene",
#     filial_id: [5, 6].sample,
#     critical_stock: rand(1..10),
#     show_in_marketplace: true,
#     description: "Descrição do Item #{i + 1}",
#     price: rand(10.0..1000.0).round(2)
#   )
# end
