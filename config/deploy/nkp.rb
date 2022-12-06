set :stage, :production
server '10.10.0.116', user: 'deploy', roles: %w{web app db}
