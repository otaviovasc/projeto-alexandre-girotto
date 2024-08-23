Rails.application.routes.draw do
  # Reservas
  get 'reservas/index'
  get 'reservas/show'
  get 'reservas/new'
  get 'reservas/create'
  # Cabanas
  get 'cabanas/index'
  get 'cabanas/show'
  get 'cabanas/:cabana_id/unavailable_dates', to: 'reservas#unavailable_dates'
  devise_for :users

  # Admin namespace for full CRUD operations
  namespace :admin do
    resources :users, only: [:index, :new, :create, :edit, :update, :destroy]
    resources :cabanas do
      resources :info_da_cabanas, only: [:index, :new, :create, :edit, :update, :destroy]
    end
    resources :reservas
  end

  # Cabana listing and details
  resources :cabanas, only: [:index, :show] do
    # Create a reserva from a cabana
    resources :reservas, only: [:new, :create]
  end
  # My reservations and reservation details
  resources :reservas, only: [:index, :show]

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

  authenticated :user, ->(u) { u.client? } do
    root to: 'home#index', as: :client_root
  end

  authenticated :user, ->(u) { !u.client? } do
    root to: 'dashboard#index', as: :authenticated_root
  end

  root to: 'home#root'
end
