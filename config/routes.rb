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
      collection do
        get 'critical_stock'
      end
    end
  end

  # Admin route (authenticated as admin)
  authenticated :user do
    root to: 'dashboard#index', as: :authenticated_root
  end

  # Client route (authenticated as clent)

  # Lead root (unautheticated)
  root to: 'home#index'

end
