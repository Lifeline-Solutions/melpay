Rails.application.routes.draw do
  # config/routes.rb
  devise_for :users

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
  root "home#index"
  get 'two_factor/send_otp', to: 'two_factor#send_otp', as: :send_otp_two_factor
  get 'two_factor/verify', to: 'two_factor#verify', as: :verify_otp
  post 'two_factor/check', to: 'two_factor#check', as: :check_otp
  resources :home
  resources :clients do
    member do
      patch :approve_kyc
      patch :reject_kyc
    end
    resources :accounts, only: [:index, :new, :create]
  end
  resources :roles, only: [:new, :create, :index]

end
