# frozen_string_literal: true

Devise.secret_key = '0c1834a2b71ef050ee0cae1b8c372b45576880bddd117dc6dfd4eee76110d22ef358295e6311b1790abc51306d83aadc71ada9715ed3bd0acc4d174f37d370b5'
Devise.email_regexp = Spree::Config[:default_email_regexp]
Devise.setup do |config|
  config.parent_controller = 'StoreDeviseController'
  config.mailer = 'UserMailer'
end
