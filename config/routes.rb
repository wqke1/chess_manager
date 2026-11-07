Rails.application.routes.draw do
  root "games#index"
  resources :games, only: [:index, :show] do
    post :analyze, on: :member
    post :ask, on: :member
    post :import, on: :collection
    post :analyze_all, on: :collection
  end
  get "eval",  to: "games#eval"
  get "stats", to: "stats#index"
end
