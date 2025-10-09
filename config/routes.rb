Rails.application.routes.draw do
  root "pages#home"

  resources :playlists, only: [ :show ]
  resources :categories, only: [ :show ]
  get "whats-new", to: "pages#whats_new", as: :whats_new

      namespace :admin do
        root to: "dashboard#index"
        resources :categories
        resources :playlists do
          collection do
            post :import_spotify
            post :start_batch_update
            get :batch_update_progress
          end
          member do
            post :sync_with_spotify
          end
        end
        resources :update_sessions do
          member do
            patch :apply_changes
          end
        end
        resources :update_logs, only: [:index]
      end

  # API endpoints for infinite scroll
  get "api/playlists", to: "api/playlists#index"
  get "api/categories/:id/playlists", to: "api/playlists#by_category"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
