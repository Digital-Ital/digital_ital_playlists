class Api::AnalyticsController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :verify_authenticity_token
  
  # POST /api/analytics/track
  def track
    session_id = params[:session_id] || generate_session_id
    
    # Find or create session
    visit_session = VisitSession.find_or_initialize_by(session_id: session_id)
    
    if visit_session.new_record?
      visit_session.assign_attributes(
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        referrer: request.referrer,
        first_page: params[:url],
        started_at: Time.current,
        page_views_count: 0
      )
      visit_session.save!
    end
    
    # Update session
    visit_session.update(
      last_page: params[:url],
      ended_at: Time.current,
      page_views_count: visit_session.page_views_count + 1
    )
    
    # Create page view
    page_view = visit_session.page_views.create!(
      url: params[:url],
      page_type: params[:page_type],
      category_id: params[:category_id],
      playlist_id: params[:playlist_id],
      search_query: params[:search_query],
      action_type: params[:action_type],
      time_on_page: params[:time_on_page] || 0
    )
    
    render json: { 
      success: true, 
      session_id: session_id,
      is_bot: visit_session.is_bot
    }
  rescue => e
    Rails.logger.error "Analytics tracking error: #{e.message}"
    render json: { error: "Tracking failed" }, status: :internal_server_error
  end
  
  private
  
  def generate_session_id
    "#{Time.current.to_i}-#{SecureRandom.hex(8)}"
  end
end

