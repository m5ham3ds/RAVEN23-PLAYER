# Phase 01 — shared offline library contract

This phase spans \`m5ham3ds/RAVEN23\` and \`m5ham3ds/RAVEN23-PLAYER\`.

## Folder layout

\`\`\`text
Movies/
  RAVEN23/
    Library/
      <stable-media-key>.mp4
      <stable-media-key>.raven23.json
      SUBTITLE/
        <stable-media-key>.<track-id>.<language>.vtt
        <stable-media-key>.<track-id>.<language>.json
    Transfers/
      ...
\`\`\`

## Manifest v1

Required fields:
- \`schema\`: \`raven23.shared-media\`
- \`version\`: integer \`1\`
- \`mediaKey\`: stable opaque media key
- \`downloadId\`: primary-app download ID
- \`mediaType\`: \`movie\` or \`tv\`
- \`contentId\`: TMDB movie ID or TV-series ID
- \`episodeId\`, \`seasonNumber\`, \`episodeNumber\` for episodic media
- \`title\`, \`durationMs\`, \`quality\`, \`audioTrackName\`
- \`posterPath\`, \`backdropPath\`
- \`video\`: MediaStore URI, display name, relative path, byte length, SHA-256
- \`subtitles\`: stable track ID, language, label, source, format, HI flag, URI, filename, byte length, SHA-256 for each track
- \`updatedAtUtc\`

Never include expiring stream URLs, provider headers, scraper tokens, API secrets, session credentials or private file paths.

## Atomic publishing rules

1. Resolve completed Media3 download and validated MP4 through the existing exporter.
2. Insert a pending MediaStore video item in the canonical folder and write the file.
3. Verify published byte length and SHA-256.
4. Publish every subtitle sidecar and metadata, preserving every cached track.
5. Publish the manifest referencing stable video and subtitle row IDs/URIs.
6. Clear MediaStore pending flags only after required artifacts validate.
7. Persist canonical URI and digest in the primary download store.
8. Reopen the shared URI. Only after it plays successfully may a redundant private export be deleted.
9. Any failure removes incomplete pending rows and retains the previous valid export.

## Subtitle access

Android's READ_MEDIA_VIDEO permission does not guarantee broad access to arbitrary .srt/.vtt files. Use an explicit SAF directory grant or an appropriate MediaStore association. Do not rely on a best-effort Files query as the only way to obtain subtitle tracks.

## Delete/ownership rules

- The primary app owns Media3 download state.
- Deleting a download must not silently delete shared media already transferred or owned by another library.
- Add explicit remove-from-library semantics and ownership markers.
- The companion must handle orphaned sidecars and missing manifests without crashing.

## Tests

- Publisher failure retains private export.
- Retry reuses media key without duplicate MediaStore rows.
- Video hash and byte count round-trip.
- Every subtitle's labels/language/source/HI flag round-trip.
- Legacy public DCIM saves are recognized but never re-copied automatically.
- Both apps can reopen the same content URI.
- Local phone videos have no manifest and never qualify for account sync.
