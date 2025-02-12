class FunilMailer < ApplicationRecord
  validates :fullname, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { case_sensitive: false }
  validates :number, presence: true

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "email", "fullname", "id", "number", "updated_at"]
  end
end
