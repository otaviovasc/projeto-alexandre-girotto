Rails.application.routes.draw do
  devise_for :users

  namespace :admin do
    resources :users, only: [:index, :new, :create, :edit, :update, :destroy]
  end

  resources :filials do
    resources :items do
      member do
        patch 'increment'
        patch 'decrement'
      end
    end
  end

  authenticated :user do
    root to: 'dashboard#index', as: :authenticated_root
  end

  root to: 'home#index'
end
