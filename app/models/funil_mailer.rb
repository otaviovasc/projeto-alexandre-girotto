class FunilMailer < ApplicationRecord
  validates :fullname, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { case_sensitive: false }
  # number is optional, so no validation required unless needed.
end
