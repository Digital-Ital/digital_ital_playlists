class Api::InteractionsController < ApplicationController
  protect_from_forgery with: :null_session
  
  # POST /api/playlists/:playlist_id/share
  def track_share
    playlist = Playlist.find(params[:playlist_id])
    
    share_event = playlist.share_events.create(
      platform: params[:platform] || 'unknown',
      shared_content: params[:shared_content],
      user_agent: request.user_agent,
      referrer: request.referrer,
      ip_address: request.remote_ip
    )
    
    render json: { success: true, share_id: share_event.id }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Playlist not found" }, status: :not_found
  rescue => e
    Rails.logger.error "Error tracking share: #{e.message}"
    render json: { error: "Failed to track share" }, status: :internal_server_error
  end
  
  # POST /api/playlists/:playlist_id/react
  def react
    playlist = Playlist.find(params[:playlist_id])
    
    # Check localStorage on frontend to prevent spam, but increment server-side
    playlist.increment!(:reaction_count)
    
    render json: { success: true, reaction_count: playlist.reaction_count }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Playlist not found" }, status: :not_found
  rescue => e
    Rails.logger.error "Error adding reaction: #{e.message}"
    render json: { error: "Failed to add reaction" }, status: :internal_server_error
  end
end

