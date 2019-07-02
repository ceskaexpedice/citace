Rails.application.routes.draw do

  namespace :v1 do
    get 'kramerius', to: 'kramerius#citation'
    get 'test', to: 'kramerius#test'
  end

end
