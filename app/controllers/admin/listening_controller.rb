require "securerandom"

class Admin::ListeningController < Admin::BaseController
  def authorize
    spotify = Spotify::ListeningService.new
    state = SecureRandom.urlsafe_base64(32)
    session[:spotify_listening_oauth_state] = state

    redirect_to spotify.authorization_url(state: state), allow_other_host: true
  rescue Spotify::ListeningService::ConfigurationError => e
    redirect_to admin_root_path, alert: e.message
  end

  def callback
    expected_state = session.delete(:spotify_listening_oauth_state)

    if params[:error].present?
      redirect_to admin_root_path, alert: "Spotify authorization was not completed: #{params[:error_description] || params[:error]}."
      return
    end

    unless expected_state.present? && ActiveSupport::SecurityUtils.secure_compare(expected_state, params[:state].to_s)
      redirect_to admin_root_path, alert: "Spotify authorization could not be verified. Please try again."
      return
    end

    @refresh_token = Spotify::ListeningService.new.exchange_code(params[:code].to_s)
    response.headers["Cache-Control"] = "no-store"
  rescue Spotify::ListeningService::ConfigurationError, Spotify::ListeningService::ApiError => e
    redirect_to admin_root_path, alert: "Spotify connection failed: #{e.message}"
  end
end
