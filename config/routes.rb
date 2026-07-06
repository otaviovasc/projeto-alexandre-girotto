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

  get 'parcerias', to: 'partnership/reservas#index', as: :partnership_dashboard
  namespace :partnership, path: 'parcerias' do
    resources :reservas, only: [:create]
  end
  get 'parcerias/nova-reserva', to: 'partnership/reservas#new', as: :new_partnership_reserva

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
        patch :update_breakfast_inclusions
      end
    end
    resources :holidays, only: [:create, :destroy]  # Manage holidays globally within admin

    resources :reservas do
      member do
        patch 'update_observation'
        patch 'update_group_created'
        patch 'acknowledge_ical_date_change'
        patch 'update_service_purchase_access'
        patch 'update_service_installments'
        post 'sync_fnrh'
        post 'fnrh_check_in'
        post 'fnrh_no_show'
        post 'fnrh_checkout'
        post 'fnrh_cancel'
        post 'fnrh_bypass_precheckin'
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
  authenticated :user, ->(u) { u.partnership_agent? } do
    root to: 'partnership/reservas#index', as: :partnership_root
  end

  authenticated :user, ->(u) { !u.client? && !u.partnership_agent? } do
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
  get  'minha-reserva/inicio',   to: 'portal_reserva#inicio',   as: :portal_reserva_inicio
  get  'minha-reserva/comprados', to: 'portal_reserva#comprados', as: :portal_reserva_comprados
  get  'minha-reserva/servicos', to: 'portal_reserva#servicos', as: :portal_reserva_servicos
  get  'minha-reserva/confirmacao', to: 'portal_reserva#confirmacao', as: :portal_reserva_confirmacao
  get  'minha-reserva/confirmacao/status', to: 'portal_reserva#confirmacao_status', as: :portal_reserva_confirmacao_status
  post 'minha-reserva/adicionar',to: 'portal_reserva#adicionar',as: :portal_reserva_adicionar
  delete 'minha-reserva/remover/:id', to: 'portal_reserva#remover', as: :portal_reserva_remover
  post 'minha-reserva/pagar',    to: 'portal_reserva#pagar',    as: :portal_reserva_pagar
  delete 'minha-reserva/sair',   to: 'portal_reserva#sair',    as: :portal_reserva_sair

  # Portal público de termos e pré-check-in FNRH
  get    'termos-hospedagem',         to: 'fnrh_portal#terms', as: :fnrh_terms
  post   'termos-hospedagem/acessar', to: 'fnrh_portal#terms_access', as: :fnrh_terms_access
  get    'pre-checkin',         to: 'fnrh_portal#index',  as: :fnrh_portal
  post   'pre-checkin/acessar', to: 'fnrh_portal#access', as: :fnrh_portal_access
  get    'pre-checkin/orientacao', to: 'fnrh_portal#orientation', as: :fnrh_portal_orientation
  post   'pre-checkin/iniciar', to: 'fnrh_portal#start_precheckin', as: :fnrh_portal_start_precheckin
  get    'pre-checkin/aguardando', to: 'fnrh_portal#waiting', as: :fnrh_portal_waiting
  post   'pre-checkin/verificar', to: 'fnrh_portal#verify', as: :fnrh_portal_verify
  get    'pre-checkin/informacoes', to: 'fnrh_portal#information', as: :fnrh_portal_information
  delete 'pre-checkin/sair',    to: 'fnrh_portal#logout', as: :fnrh_portal_logout

  namespace :fnrh, path: 'fnrh-simulacao' do
    get  'precheckin/:reservation_id', to: 'mock#precheckin', as: :mock_precheckin
    post 'precheckin/:reservation_id/complete', to: 'mock#complete_precheckin', as: :mock_complete_precheckin
  end

  # Unlogged route
  root to: 'home#root'
end
