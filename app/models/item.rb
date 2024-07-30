class Item < ApplicationRecord
  belongs_to :filial

  CATEGORIES = ["Limpeza e Higiene",
  "Alimentação e Bebidas",
  "Utensílios de Cozinha",
  "Cama e Banho",
  "Mobiliário e Decoração",
  "Manutenção e Reparos",
  "Conforto e Lazer",
  "Segurança",
  "Tecnologia e Eletrônicos",
  "Papelaria e Escritório",
  "Produtos de Hospitalidade",
  "Roupas e Uniformes"]

  validates :name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :critical_stock, numericality: { greater_than_or_equal_to: 0 }


  has_one_attached :image
end
