Rails.application.routes.draw do
  get 'services/show'
  get 'items/show'
  # Reservas
  get 'reservas/index'
  get 'reservas/show'
  get 'reservas/new'
  get 'reservas/create'
  # Cabanas
  get 'cabanas/index'
  get 'cabanas/show'
  get 'cabanas/:cabana_id/unavailable_dates', to: 'reservas#unavailable_dates'
  get 'cabanas/:id/region', to: 'cabanas#region', as: 'cabana_region'
  devise_for :users, controllers: { registrations: 'users/registrations' }

  # Static page
  get 'about', to: 'home#about'
  get 'experiencias', to: 'home#experiencias'
  get 'sustentabilidade', to: 'home#sustentabilidade'

  # Funil mailer
  post 'crete_mailer_entry', to: 'home#create_mailer_entry'

  # Admin namespace for full CRUD operations
  namespace :admin do
    resources :users, only: [:index, :new, :create, :edit, :update, :destroy] do
      member do
        get :partner_status
        patch :update_partner_status
      end
    end
  
    resources :funil_mailers, only: [:index, :show]

    resources :cabanas do
      resources :info_da_cabanas, only: [:index, :new, :create, :edit, :update, :destroy]
      resources :price_rules, only: [:create, :destroy]  # For handling price rules within cabanas
      resources :promotions, only: [:create, :destroy]  # Adicionando promoções para cada cabana
      member do
        get 'price_rules_and_holidays'  # Route for the combined form
        delete 'remove_image/:image_id', to: 'cabanas#remove_image', as: 'remove_image'
        get :edit_import_links
        patch :update_import_links
      end
    end
    resources :holidays, only: [:create, :destroy]  # Manage holidays globally within admin

    resources :reservas do
      member do
        patch 'update_observation'
      end
      collection do
        get :import_airbnb_calendar
        get :reservas_summary
        get :export_csv
        get :export_sheets

        get :plataformas_import
        get :select_cabana_import

        post :import_platform_calendar
      end
    end
   get 'reservas_summary', to: 'reservas#reservas_summary'

    resources :services do
      member do
        delete 'remove_image/:image_id', to: 'services#remove_image', as: 'remove_image'
      end
    end

    resources :service_purchases, only: [:index]

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
  resources :reservas, only: [:index, :show] do
    collection do
      get :auto_create
    end
    get 'pay', on: :member  # Process payment for a reservation
    resources :reserva_services, only: [:create]
    resources :reserva_items, only: [:create]
  end

  post 'pagamentos/webhook', to: 'pagamentos#webhook', as: 'pagamentos_webhook'

  # Cart
  post 'cart/add_item', to: 'carts#add_item', as: 'add_item'
  post 'cart/update_item', to: 'carts#update_item', as: 'update_item'
  delete 'cart/remove_item/:id', to: 'carts#remove_item', as: 'remove_item'
  get 'cart/checkout', to: 'carts#checkout', as: 'checkout_cart'
  get 'cart/payment', to: 'carts#payment', as: 'payment_cart'  # Payment page
  post 'cart/checkout', to: 'carts#checkout_process', as: 'checkout_process'

  # Marketplace
  resources :marketplace, only: [] do
    collection do
      get 'services'
      get 'items'
    end
  end

  # Use the actual item and service controllers for show actions
  resources :items, only: [:show]
  resources :services, only: [:show]

  # Client Auth route
  authenticated :user, ->(u) { u.client? } do
    root to: 'reservas#index', as: :client_root
  end

  # Admin root
  authenticated :user, ->(u) { !u.client? } do
    root to: 'dashboard#index', as: :authenticated_root
  end

  # Rota acessível para admin visualizar a página pública
  get '/home_root', to: 'home#root', as: :home_root

  namespace :public do
   get "cabana/:id", to: "calendar#export", as: :calendar_export
  end

  # Portal da Reserva (acesso sem login obrigatório via ID + nome/email)
  get  'minha-reserva',          to: 'portal_reserva#index',    as: :portal_reserva
  post 'minha-reserva/acessar',  to: 'portal_reserva#acessar',  as: :portal_reserva_acessar
  get  'minha-reserva/servicos', to: 'portal_reserva#servicos', as: :portal_reserva_servicos
  get  'minha-reserva/confirmacao', to: 'portal_reserva#confirmacao', as: :portal_reserva_confirmacao
  get  'minha-reserva/confirmacao/status', to: 'portal_reserva#confirmacao_status', as: :portal_reserva_confirmacao_status
  post 'minha-reserva/adicionar',to: 'portal_reserva#adicionar',as: :portal_reserva_adicionar
  delete 'minha-reserva/remover/:id', to: 'portal_reserva#remover', as: :portal_reserva_remover
  post 'minha-reserva/pagar',    to: 'portal_reserva#pagar',    as: :portal_reserva_pagar
  delete 'minha-reserva/sair',   to: 'portal_reserva#sair',    as: :portal_reserva_sair

  # Unlogged route
  root to: 'home#root'
end
