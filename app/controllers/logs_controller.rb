class LogsController < ApplicationController

  def index
    limit = (params[:limit] || 100).to_i
    offset = (params[:offset] || 0).to_i
    citations = Log.all
    count = citations.count
    citations = citations.order(timestamp: :desc).offset(offset).limit(limit)
    render status: 200, json: {
      count: count,
      limit: limit,
      offset: offset,
      citations: citations
    }
  end

  def group
    data = Log.all.group(params[:by] || "kramerius").count
    render status: 200, json: Hash[data.sort_by{ |_, v| -v }[0...200]]
    
  end
  
end
