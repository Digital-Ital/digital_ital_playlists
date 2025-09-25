class Admin::BaseController < ApplicationController
  before_action :authenticate

  private

  def authenticate
    admin_user = ENV.fetch('ADMIN_USER', 'admin')
    admin_pass = ENV.fetch('ADMIN_PASSWORD', 'digitalital!')
    authenticate_or_request_with_http_basic('Admin Area') do |u, p|
      ActiveSupport::SecurityUtils.secure_compare(u, admin_user) && ActiveSupport::SecurityUtils.secure_compare(p, admin_pass)
    end
  end
end
