Rails.application.routes.draw do

  namespace :v1 do
    get 'kramerius', to: 'kramerius#citation'
  end

end
