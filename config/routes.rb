# config/routes.rb
Rails.application.routes.draw do
  devise_for :users, controllers: { sessions: 'users/sessions', invitations: 'invitations' }

  get "up" => "rails/health#show", as: :rails_health_check
  root "home#index"

  get 'two_factor/send_otp', to: 'two_factor#send_otp', as: :send_otp_two_factor
  get 'two_factor/verify', to: 'two_factor#verify', as: :verify_otp
  post 'two_factor/check', to: 'two_factor#check', as: :check_otp
  post 'two_factor/cancel_pending', to: 'two_factor#cancel_pending', as: :cancel_pending_two_factor

  resources :users, only: [:index, :show, :edit, :update]
  resources :home do
    member do
      post :pay_single_deposit
      post :pay_all_deposits
    end
  end
  resources :interest_rates, only: [:index, :edit, :update] do
    collection do
      get :manage
      put :update_global
      put :update_custom
    end
  end
  
  resources :clients do
    member do
      patch :approve_kyc
      patch :reject_kyc
    end
  end
  resources :roles, only: [:new, :create, :index]
  resources :transactions, only: [:new, :create, :index, :show] do
    member do
      patch :update_status
    end
  end
end