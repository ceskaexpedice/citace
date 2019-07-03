class LogsController < ApplicationController

  def index
    logs = Log.all.order(timestamp: :desc)
    render status: 200, json: logs
  end
  
end
