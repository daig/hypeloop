# Changelog

## [Unreleased] – 2025-02-07

### Added
- **Swipe Gestures & Visual Feedback:**  
  - Introduced new swipeable components for the video feed.  
  - Distinct swipe actions (up, down, left, right) now trigger like/dislike, share, and save actions with clear visual indicators (thumbs, airplane, checkmark icons).

- **Enhanced Video Player Interactions:**  
  - Tapping on a playing video now shows a pause indicator; tapping on a paused video shows a play indicator.  
  - Double-tap gestures quickly restart a video with a visible restart icon.
  
- **"Caught Up" Screen:**  
  - Added a dedicated screen that informs you when there are no more videos to watch, along with a one-tap refresh button.
  
- **Refined Video Upload Flow:**  
  - The “Create” tab now optimizes videos before upload.  
  - A progress bar shows upload progress, and a checkmark confirms successful uploads.
  
- **Simplified Logout Functionality:**  
  - Integrated a context menu on navigation buttons to allow easy sign-out from anywhere in the app.
  
- **Improved Saved Videos View:**  
  - Redesigned the saved videos grid with clear preview thumbnails and integrated download functionality.  
  - Long-press actions enable deletion or copying of video links.
  
- **User-Friendly Creator Names:**  
  - New pseudorandom display names are generated from hashed user identifiers, ensuring consistent and appealing creator labels.
  
- **Under-the-Hood Enhancements:**  
  - Introduced a Bloom Filter mechanism to track seen videos and prevent repeats.  
  - Added helper extensions for video preloading, navigation, and swipe handling.
  - Implemented a migration script to move Mux metadata into Firebase Firestore.
  - Integrated Firebase authentication persistence and refined Firestore security rules and indexes.

### Changed
- **Video Playback & Looping:**  
  - Improved buffering, smoother looping, and refined playback controls for a more reliable video experience.
  
- **Code Refactoring:**  
  - Split and reorganized video management logic into multiple extensions (preloading, navigation, swipe handlers) for better maintainability.
  - Updated UI elements including navigation bar gradients and overall layout refinements.
  
- **Dependency Updates:**  
  - Upgraded various package dependencies (Firebase, Mux, and supporting libraries) to their latest versions.
  
- **Error Handling & Logging:**  
  - Enhanced error logging in Mux webhook processing and video upload flows.
  - Implemented signature verification in the webhook endpoint for improved security.

### Fixed
- **Playback Issues:**  
  - Resolved occasional video freezing and audio playback issues at the end of the feed.
  
- **Upload UI Bugs:**  
  - Fixed UI glitches during the upload process so that the checkmark indicator appears on successful uploads.
  
- **Metadata Persistence:**  
  - Corrected the handling of creator metadata to ensure the proper display name and creator hash are saved.

### Deprecated
- None

### Removed
- **Legacy Code:**  
  - Eliminated redundant authentication checks in the video creation view.  
  - Removed outdated video preloading and looping methods in favor of newer, more efficient approaches.

### Security
- **Webhook Verification:**  
  - Enhanced Mux webhook security by verifying signature headers against the configured secret.
  
- **Firestore Rules:**  
  - Updated Firestore security rules to enforce stricter access based on authenticated user credentials.


## [Unreleased] - 2025 - 02 - 05

### Added
- **Brainlift Document**: Introduces a high-level architecture overview for Hypeloop. [(e8560ce)](https://example.com/commit/e8560ce)
- **Apple ID Sign-In**: Implements Apple Sign In flows with Firebase integration for a smoother login experience. [(3969040)](https://example.com/commit/3969040) [(0b2d7e0)](https://example.com/commit/0b2d7e0)

### Changed
- **Logout Option**: Added a logout shortcut via long-press on the Home icon. [(0c4f21e)](https://example.com/commit/0c4f21e)
- **Video Overlay**: Moved creator and description text onto the video card in the home feed. [(6fcd3fd)](https://example.com/commit/6fcd3fd)
- **Mux Upload Metadata**: Video uploads now include creator and description fields sent to Mux. [(2f57a3b)](https://example.com/commit/2f57a3b)
- **Saved Videos Gallery**: Transitioned saved videos to a grid-based gallery layout. [(ced6b99)](https://example.com/commit/ced6b99)
- **Real Mux Playlist**: Replaced placeholder playback IDs with a dynamic list fetched from Mux. [(520214b)](https://example.com/commit/520214b)

### Removed
- **Upload Popup**: Eliminated the upload pop-up for a more streamlined interface. [(f5a1967)](https://example.com/commit/f5a1967)
- **Testing Button**: Removed a debug/testing button from the `CreateTabView`. [(412bfa3)](https://example.com/commit/412bfa3)
- **Search Tab**: Dropped the separate Search tab from the navigation. [(07349df)](https://example.com/commit/07349df)

### Fixed
- **Upload Progress Bar**: Corrected issues preventing accurate upload progress display. [(c19eb26)](https://example.com/commit/c19eb26)
- **Saved Video Card Layout**: Addressed oversize rendering in the Saved Videos tab. [(c9a0abd)](https://example.com/commit/c9a0abd)
- **Mux Metadata Parsing**: Properly retrieves and displays creator name and description from passthrough JSON. [(aae9e65)](https://example.com/commit/aae9e65)
- **Playback on Refresh**: Ensured the next video auto-plays immediately after refresh. [(0b20b53)](https://example.com/commit/0b20b53)

---

*Generated using the [Keep a Changelog](https://keepachangelog.com) format.*