class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:root]

  def root
  end

  def index
  end
end
