# frozen_string_literal: true

class User < ApplicationRecord
  validates :email, presence: true, uniqueness: true
  validates :password_digest, presence: true

  has_secure_password

  def authenticate(password)
    BCrypt::Password.new(password_digest) == password
  end

  def self.find_by_email(email)
    where(email: email).first
  end
end
