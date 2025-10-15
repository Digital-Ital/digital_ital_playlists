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

  # Optimized version that reuses an access token
  def call_with_token(access_token)
    return call unless access_token # Fallback to normal method if no token provided
    
    # Quick check first - skip if no track changes
    spotify_service = Spotify::PlaylistSyncService.new(@playlist)
    result = spotify_service.quick_check_with_token(access_token)
    
    # If no changes detected, skip processing
    if result[:skip]
      Rails.logger.info "Skipped playlist #{@playlist.id}: #{result[:reason]}"
      return {
        success: true,
        changes: [],
        playlist: @playlist,
        skipped: true,
        reason: result[:reason]
      }
    end

    # Track count changed - do full sync
    spotify_data = result

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
    # Build a map of existing playlist track associations by track_id -> position
    existing_track_id_to_position = @playlist.playlist_tracks.pluck(:track_id, :position).to_h
    spotify_track_ids = []

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

      # Update track info only if it actually changed (avoid unnecessary DB writes)
      track_attributes = {
        name: track_data[:name],
        artist: track_data[:artist],
        album: track_data[:album],
        image_url: track_data[:image_url],
        duration_ms: track_data[:duration_ms],
        preview_url: track_data[:preview_url],
        external_url: track_data[:external_url]
      }
      
      # Only update if any field actually changed
      if track.name != track_attributes[:name] ||
         track.artist != track_attributes[:artist] ||
         track.album != track_attributes[:album] ||
         track.image_url != track_attributes[:image_url] ||
         track.duration_ms != track_attributes[:duration_ms] ||
         track.preview_url != track_attributes[:preview_url] ||
         track.external_url != track_attributes[:external_url]
        track.update!(track_attributes)
      end

      spotify_track_ids << track.id

      # Determine if this track is already associated to this playlist
      if existing_track_id_to_position.key?(track.id)
        # Track exists but position may have changed
        existing_position = existing_track_id_to_position[track.id]
        if existing_position != track_data[:position]
          @playlist.playlist_tracks.where(track_id: track.id).update_all(position: track_data[:position])
        end
      else
        # New track for this playlist: create association with correct added_at and position
        @playlist.playlist_tracks.create!(
          track_id: track.id,
          added_at: track_data[:added_at],
          position: track_data[:position]
        )
        log_track_added(track)
      end
    end

    # Find removed tracks (tracks in our DB but not in Spotify response)
    current_track_ids_in_db = existing_track_id_to_position.keys
    removed_track_ids = current_track_ids_in_db - spotify_track_ids
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

