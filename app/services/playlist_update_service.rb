class PlaylistUpdateService
  def initialize(playlist)
    @playlist = playlist
    @changes = []
  end

  def call
    # Fetch fresh data from Spotify
    spotify_service = Spotify::PlaylistSyncService.new(@playlist)
    spotify_data = spotify_service.sync

    ActiveRecord::Base.transaction do
      # Update playlist metadata and log changes
      update_metadata(spotify_data[:metadata])
      
      # Sync tracks and log additions/removals
      sync_tracks(spotify_data[:tracks])
      
      # Update last_updated_at timestamp
      @playlist.update!(last_updated_at: Time.current)
    end

    {
      success: true,
      changes: @changes,
      playlist: @playlist
    }
  rescue => e
    Rails.logger.error "Failed to update playlist #{@playlist.id}: #{e.message}"
    {
      success: false,
      error: e.message,
      playlist: @playlist
    }
  end

  private

  def update_metadata(metadata)
    changed_fields = []

    # Check each metadata field for changes
    if @playlist.title != metadata[:title]
      log_metadata_change('title', @playlist.title, metadata[:title])
      changed_fields << :title
    end

    if @playlist.description != metadata[:description]
      log_metadata_change('description', @playlist.description, metadata[:description])
      changed_fields << :description
    end

    if @playlist.cover_image_url != metadata[:cover_image_url]
      log_metadata_change('cover_image_url', @playlist.cover_image_url, metadata[:cover_image_url])
      changed_fields << :cover_image_url
    end

    if @playlist.track_count != metadata[:track_count]
      log_metadata_change('track_count', @playlist.track_count, metadata[:track_count])
      changed_fields << :track_count
    end

    if @playlist.followers_count != metadata[:followers_count]
      log_metadata_change('followers_count', @playlist.followers_count, metadata[:followers_count])
      changed_fields << :followers_count
    end

    # Update the playlist if there are changes
    if changed_fields.any?
      @playlist.update!(
        title: metadata[:title],
        description: metadata[:description],
        cover_image_url: metadata[:cover_image_url],
        track_count: metadata[:track_count],
        followers_count: metadata[:followers_count]
      )
    end
  end

  def sync_tracks(spotify_tracks)
    # Get current tracks in our database
    current_track_ids = @playlist.playlist_tracks.pluck(:track_id, :position).to_h.invert
    spotify_track_ids = {}

    # Process each track from Spotify
    spotify_tracks.each do |track_data|
      # Find or create the track
      track = Track.find_or_create_by!(spotify_id: track_data[:spotify_id]) do |t|
        t.name = track_data[:name]
        t.artist = track_data[:artist]
        t.album = track_data[:album]
        t.image_url = track_data[:image_url]
        t.duration_ms = track_data[:duration_ms]
        t.preview_url = track_data[:preview_url]
        t.external_url = track_data[:external_url]
      end

      # Update track info if it exists (in case Spotify metadata changed)
      track.update!(
        name: track_data[:name],
        artist: track_data[:artist],
        album: track_data[:album],
        image_url: track_data[:image_url],
        duration_ms: track_data[:duration_ms],
        preview_url: track_data[:preview_url],
        external_url: track_data[:external_url]
      )

      spotify_track_ids[track_data[:position]] = track.id

      # Check if this is a new track for this playlist
      unless current_track_ids.key?(track_data[:position]) && current_track_ids[track_data[:position]] == track.id
        # Find or update the playlist_track association
        playlist_track = @playlist.playlist_tracks.find_or_initialize_by(track_id: track.id)
        
        if playlist_track.new_record?
          # New track - log it
          playlist_track.assign_attributes(
            added_at: track_data[:added_at],
            position: track_data[:position]
          )
          playlist_track.save!
          
          log_track_added(track)
        else
          # Track exists but position might have changed
          if playlist_track.position != track_data[:position]
            playlist_track.update!(position: track_data[:position])
          end
        end
      end
    end

    # Find removed tracks (tracks in our DB but not in Spotify response)
    removed_track_ids = current_track_ids.values - spotify_track_ids.values
    removed_track_ids.each do |track_id|
      track = Track.find(track_id)
      @playlist.playlist_tracks.where(track_id: track_id).destroy_all
      log_track_removed(track)
    end
  end

  def log_metadata_change(field_name, old_value, new_value)
    UpdateLog.create!(
      playlist: @playlist,
      log_type: 'playlist_metadata',
      field_name: field_name,
      old_value: old_value.to_s,
      new_value: new_value.to_s,
      change_summary: "#{field_name.humanize} changed from '#{old_value}' to '#{new_value}'"
    )
    @changes << { type: 'metadata', field: field_name, old: old_value, new: new_value }
  end

  def log_track_added(track)
    UpdateLog.create!(
      playlist: @playlist,
      track: track,
      log_type: 'track_added',
      change_summary: "Added track: #{track.display_name}"
    )
    @changes << { type: 'track_added', track: track }
  end

  def log_track_removed(track)
    UpdateLog.create!(
      playlist: @playlist,
      track: track,
      log_type: 'track_removed',
      change_summary: "Removed track: #{track.display_name}"
    )
    @changes << { type: 'track_removed', track: track }
  end
end

