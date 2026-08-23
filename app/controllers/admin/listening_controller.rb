require "securerandom"
require "uri"

class Admin::ListeningController < Admin::BaseController
  def show
    @spotify = Spotify::ListeningService.new
    @setup = @spotify.setup_status
    @configured_callback_uri = parse_callback_uri(@setup[:redirect_uri])
    @configured_callback_host = @configured_callback_uri&.host
    @configured_callback_scheme = @configured_callback_uri&.scheme
    @request_host = request.host
    @request_scheme = request.ssl? ? "https" : "http"
    @callback_host_matches = @configured_callback_host.present? && @configured_callback_host.casecmp?(@request_host)
    @callback_uses_https = @configured_callback_scheme == "https"
    @request_uses_https = request.ssl?
    @connection_error = connection_error_message(params[:connection_error])
  end

  def authorize
    spotify = Spotify::ListeningService.new

    unless spotify.authorization_ready?
      redirect_to admin_listening_path(connection_error: "missing_configuration")
      return
    end

    callback_uri = parse_callback_uri(spotify.setup_status[:redirect_uri])

    unless callback_uri&.scheme == "https"
      redirect_to admin_listening_path(connection_error: "insecure_callback")
      return
    end

    unless request.ssl?
      redirect_to admin_listening_path(connection_error: "insecure_request")
      return
    end

    unless callback_uri.host&.casecmp?(request.host)
      redirect_to admin_listening_path(connection_error: "callback_host_mismatch")
      return
    end

    state = SecureRandom.urlsafe_base64(32)
    session[:spotify_listening_oauth_state] = state

    redirect_to spotify.authorization_url(state: state), allow_other_host: true
  rescue Spotify::ListeningService::ConfigurationError
    redirect_to admin_listening_path(connection_error: "missing_configuration")
  end

  def callback
    expected_state = session.delete(:spotify_listening_oauth_state)

    if params[:error].present?
      redirect_to admin_listening_path(connection_error: "spotify_denied")
      return
    end

    unless expected_state.present? && ActiveSupport::SecurityUtils.secure_compare(expected_state, params[:state].to_s)
      redirect_to admin_listening_path(connection_error: "callback_state_mismatch")
      return
    end

    @refresh_token = Spotify::ListeningService.new.exchange_code(params[:code].to_s)
    response.headers["Cache-Control"] = "no-store"
  rescue Spotify::ListeningService::ConfigurationError
    redirect_to admin_listening_path(connection_error: "missing_configuration")
  rescue Spotify::ListeningService::ApiError
    redirect_to admin_listening_path(connection_error: "token_exchange_failed")
  end

  private

  def parse_callback_uri(uri)
    URI.parse(uri.to_s)
  rescue URI::InvalidURIError, TypeError
    nil
  end

  def connection_error_message(code)
    {
      "missing_configuration" => "The server is missing Spotify configuration. Check the three required configuration entries below.",
      "insecure_request" => "You opened this page over HTTP. Spotify requires an HTTPS callback for production apps, so the connection is intentionally blocked until the Heroku certificate is issued.",
      "insecure_callback" => "The configured callback URL uses HTTP. Spotify requires HTTPS for production callbacks; update it in both Spotify and Heroku after HTTPS is working.",
      "callback_host_mismatch" => "The configured callback hostname does not match the address in your browser. Use one hostname consistently before connecting.",
      "spotify_denied" => "Spotify authorization was cancelled or denied. Nothing was connected.",
      "callback_state_mismatch" => "Spotify returned to a different browser session or hostname. Start the connection from this page and make sure the configured callback host matches the address in your browser.",
      "token_exchange_failed" => "Spotify accepted the redirect, but the server could not exchange it for a refresh token. Reconnect from this page; if it repeats, check the exact callback URL in Spotify and Heroku."
    }[code]
  end
end
