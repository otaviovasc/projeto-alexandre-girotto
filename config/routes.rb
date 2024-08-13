Rails.application.routes.draw do
  get 'reservas/index'
  get 'reservas/show'
  get 'reservas/new'
  get 'reservas/create'
  get 'cabanas/index'
  get 'cabanas/show'
  devise_for :users

  # Admin namespace for full CRUD operations
  namespace :admin do
    resources :users, only: [:index, :new, :create, :edit, :update, :destroy]
    resources :cabanas do
      resources :info_da_cabanas, only: [:index, :new, :create, :edit, :update, :destroy]
    end
    resources :reservas
  end

  # Client-facing routes
  resources :cabanas, only: [:index, :show] do
    resources :reservas, only: [:new, :create]
  end
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
    root to: 'reservas#index', as: :client_root
  end

  authenticated :user, ->(u) { !u.client? } do
    root to: 'dashboard#index', as: :authenticated_root
  end

  root to: 'home#index'
end
