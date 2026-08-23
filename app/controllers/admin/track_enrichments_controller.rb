class Admin::TrackEnrichmentsController < Admin::BaseController
  before_action :set_track
  before_action :set_enrichment

  def show
    @enrichment.expire_temporary_claims!
    @discogs_configured = ENV["DISCOGS_USER_TOKEN"].present?
    @discogs_search_url = "https://www.discogs.com/search/?type=release&q=#{ERB::Util.url_encode([ @track.artist, @track.name ].join(" "))}"
  end

  def update
    supplied_value = params[:discogs_release_id].to_s
    release_id = discogs_release_id_from(supplied_value)

    if supplied_value.present? && release_id.blank?
      redirect_to admin_track_enrichment_path(@track), alert: "Paste a Discogs release ID or a Discogs release URL."
      return
    end

    @enrichment.set_discogs_release_id!(release_id)
    redirect_to admin_track_enrichment_path(@track), notice: "Discogs release selection saved. Refresh source evidence to load it."
  end

  def refresh
    @enrichment = MusicMetadata::TrackDossierRefreshService.new(@track).call

    message = if @enrichment.status == "refreshing"
      "A source refresh is already in progress for this track."
    elsif @enrichment.last_error.present?
      "Refresh completed with a problem: #{@enrichment.last_error}"
    elsif @enrichment.ready?
      "Source evidence refreshed. Read each source scope before treating two dates or credits as the same fact."
    else
      "No high-confidence source evidence was found yet."
    end

    redirect_to admin_track_enrichment_path(@track), notice: message
  end

  private

  def set_track
    @track = Track.find(params[:id])
  end

  def set_enrichment
    @enrichment = TrackEnrichment.find_or_create_by!(track: @track)
  end

  def discogs_release_id_from(value)
    return value if value.match?(/\A\d+\z/)

    value[%r{discogs\.com/(?:[^/]+/)?release/(\d+)}i, 1] ||
      value[%r{\Arelease/(\d+)}i, 1]
  end
end
