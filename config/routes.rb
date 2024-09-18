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

  # Static page
  get 'about', to: 'home#about'
  get 'experiencias', to: 'home#experiencias'



  # Funil mailer
  post 'crete_mailer_entry', to: 'home#create_mailer_entry'

  # Admin namespace for full CRUD operations
  namespace :admin do
    resources :users, only: [:index, :new, :create, :edit, :update, :destroy]

    resources :cabanas do
      resources :info_da_cabanas, only: [:index, :new, :create, :edit, :update, :destroy]
      resources :price_rules, only: [:create, :destroy]  # For handling price rules within cabanas
      member do
        get 'price_rules_and_holidays'  # Route for the combined form
      end
    end
    resources :holidays, only: [:create, :destroy]  # Manage holidays globally within admin

    resources :reservas

    resources :filials do
      resources :items do
        collection do
          get 'critical_stock'
        end
      end
    end
  end

  # Cabana listing and details
  resources :cabanas, only: [:index, :show] do
    resources :reservas, only: [:new, :create] do # Create a reserva from a cabana
      get 'calculate_price', on: :collection  # route for calculating price dynamicall
    end
  end
  # My reservations and reservation details
  resources :reservas, only: [:index, :show]


  # Client Auth route
  authenticated :user, ->(u) { u.client? } do
    root to: 'home#index', as: :client_root
  end

  # Admin root
  authenticated :user, ->(u) { !u.client? } do
    root to: 'dashboard#index', as: :authenticated_root
  end

  # Unlogged route
  root to: 'home#root'
end
