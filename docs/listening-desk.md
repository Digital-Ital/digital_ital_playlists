# Listening Desk

The public Listening Desk is available at `/listening`. It searches the latest Digital Ital database first—by song title, artist, and album—and reports the playlist placements, crate categories, playlist position, and artist/album footprints already held in the database.

## Spotify usage

Spotify is used only for the shared **Now Playing** and **Recent listens** panels:

- current playback is shared-cached for 20 seconds;
- recent listening history is shared-cached for 60 seconds;
- a page request reuses one access token for both calls;
- local crate search and all curation intelligence make no Spotify API calls.

No playback audio is streamed or stored.

## One-time owner connection

Existing `SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET` are reused.

1. In the Spotify Developer Dashboard, add this exact Redirect URI:
   `https://italcrates.com/admin/listening/spotify/callback`
2. In Heroku Config Vars, set the exact same URI as:
   `SPOTIFY_LISTENING_REDIRECT_URI`
3. Deploy the change, then sign in to the protected admin dashboard and visit:
   `/admin/listening`
4. Use the status screen to verify the configured callback host matches the hostname in your browser, then choose **Connect Spotify**.
5. Approve Spotify access. The callback shows a clear one-time refresh-token screen.
6. Add that value in Heroku as:
   `SPOTIFY_LISTENING_REFRESH_TOKEN`

If DNS is still propagating, use the current `*.herokuapp.com` hostname in both places instead. The Spotify redirect URI and the Heroku config variable must match exactly.

The refresh token is not written to the database, rendered after leaving the callback page, or committed to GitHub.
