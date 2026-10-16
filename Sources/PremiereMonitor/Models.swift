import Foundation

/// Download quality, chosen per premiere at add/edit time from a YouTube-style
/// dropdown (1080p Premium at top when ever confirmed, then Best/resolution
/// caps) — labeled and ordered to match YouTube's own quality menu, verified
/// 15-10-2026 directly against a real Premium account: YouTube writes it as
/// "1080p Premium" (no asterisk, tied to the resolution it enhances, not a
/// standalone "Premium") with a one-line explanation underneath, positioned
/// above plain "1080p". AddVideoView mirrors the label/position; the inline
/// per-item subtitle itself is AppKit-only (NSMenuItem.subtitle, macOS
/// 14.4+) and deliberately skipped here to avoid a compatibility gap on
/// anything older — a plain caption below the picker carries the same
/// explanation instead.
/// Optional on MonitoredVideo (nil-default) for the same decode-compatibility
/// reason as the flags below — existing saved premieres without this field
/// just fall back to .best, today's only behavior.
///
/// Resolved entirely at download time via a live yt-dlp -f filter rather than
/// anything looked up and stored in advance: a premiere is typically added
/// days before it airs, when yt-dlp has no real format list for it yet (it
/// doesn't exist until the stream starts) — so there's nothing meaningful to
/// pre-resolve at add-time anyway. .premium in particular never needs a
/// stored format_id: its filter just looks for YouTube's own "Premium"
/// format_note tag at download time and is a no-op when nothing matches, so
/// it quietly degrades to exactly .best's result on any video without one.
///
/// Confirmed 15-10-2026 against a real Premium account/video: YouTube labels
/// the enhanced-bitrate track's format_note literally as e.g. "1080p Premium"
/// — and, on that video, only as vp9/av01, not avc1/h264 at all. So unlike
/// .best/the resolution caps below (which stay pinned to avc1 for playback
/// compatibility), .premium's filter intentionally doesn't codec-restrict —
/// requiring avc1 would have silently filtered the real Premium track away.
enum VideoQuality: String, Codable, CaseIterable, Identifiable {
    case premium = "Premium"
    case best = "Best"
    case p1080 = "P1080"
    case p720 = "P720"
    case p480 = "P480"
    case p360 = "P360"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .premium: return "1080p Premium"
        case .best: return "Best available"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .p360: return "360p"
        }
    }

    /// Non-private so MonitorEngine's lookupVideoInfo can filter the add-screen's
    /// dropdown down to tiers that genuinely exist for a given video, when it already
    /// has a real format list to check against (see availableQualities(meta:)).
    var heightCap: Int? {
        switch self {
        case .p1080: return 1080
        case .p720: return 720
        case .p480: return 480
        case .p360: return 360
        case .best, .premium: return nil
        }
    }

    /// yt-dlp -f filter. .premium tries a Premium-tagged track first (any
    /// codec — see above), then falls through to the exact same avc1-best
    /// selector as .best whenever nothing matches.
    ///
    /// "bv" here, not "bv*": the asterisk relaxes yt-dlp's video-only
    /// requirement, letting it also consider pre-combined formats (itag 18,
    /// a single 360p stream with audio baked in) as a "video" candidate.
    /// Verified 15-10-2026: combined with this app's own "-S codec:h264,res"
    /// sort override, that let itag 18 outrank the real 1080p/720p video-only
    /// track and silently resolve to 360p instead — reproduced 3/3 with
    /// "bv*", fixed 3/3 by switching to plain "bv", independent of cookies
    /// (so the existing cookie-retry fallback elsewhere never would have
    /// caught this). Initially misdiagnosed as a YouTube-side "SABR
    /// streaming experiment" warning seen in passing during the same
    /// investigation — that warning was real but unrelated to this.
    var formatFilter: String {
        let avc1Best = heightCap.map { "bv[vcodec^=avc1][height<=\($0)]+ba/b" } ?? "bv[vcodec^=avc1]+ba/b"
        guard self == .premium else { return avc1Best }
        return "bv[format_note*=Premium]+ba/" + avc1Best
    }
}

enum VideoStatus: String, Codable {
    // Raw values are kept stable (not translated) so existing saved data keeps decoding correctly.
    case waiting = "Wachten"
    case downloadingLive = "LIVE downloaden"
    case vodPending = "Wacht op VOD"
    case downloadingVod = "VOD downloaden"
    case done = "Klaar"

    var displayName: String {
        switch self {
        case .waiting: return "Waiting"
        case .downloadingLive: return "Downloading LIVE"
        case .vodPending: return "Waiting for HD VOD"
        case .downloadingVod: return "Downloading VOD"
        case .done: return "Done"
        }
    }

    var color: String {
        switch self {
        case .waiting: return "gray"
        case .downloadingLive: return "red"
        case .vodPending: return "orange"
        case .downloadingVod: return "blue"
        case .done: return "green"
        }
    }
}

struct MonitoredVideo: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var url: String
    var label: String
    var scheduledDate: Date
    var status: VideoStatus = .waiting
    var liveDone: Bool = false
    var vodDone: Bool = false
    var lastChecked: Date? = nil
    var finalFilePath: String? = nil
    /// Of de "premiere is live"-melding al verstuurd is. Losgekoppeld van
    /// liveDone, want dat vlaggetje gaat pas aan bij een geslaagde download —
    /// waardoor een mislukking elke ronde opnieuw dezelfde melding stuurde.
    ///
    /// Optioneel, en dat is geen slordigheid: Swift gebruikt standaardwaarden
    /// níet bij het decoderen, dus een niet-optioneel veld laat het inlezen van
    /// een bestaande videos.json mislukken. Store.swift vangt dat af met
    /// `?? []` — je lijst is dan stilzwijgend leeg en er wordt niets meer
    /// bewaakt. Precies dat gebeurde op 19-09-2026.
    var liveNotified: Bool? = nil
    /// Tot wanneer we deze video met rust laten na een mislukte poging.
    var retryNotBefore: Date? = nil
    /// Of de "nog steeds niet live, we vertragen nu"-melding al verstuurd is.
    /// Optioneel om dezelfde reden als liveNotified hierboven.
    var stillWaitingNotified: Bool? = nil
    /// Of de pre-flight-check (yt-dlp/toegang/link) 1 dag resp. 1 uur van tevoren
    /// al verstuurd is. Optioneel om dezelfde reden als liveNotified hierboven.
    var dayBeforeCheckNotified: Bool? = nil
    var hourBeforeCheckNotified: Bool? = nil
    /// When the LIVE capture finished — used to hold off starting the VOD download
    /// for a short buffer afterward. Optional for the same decode-compatibility
    /// reason as liveNotified above.
    var liveFinishedAt: Date? = nil
    /// Of de "VOD download gestart"-melding al verstuurd is — zonder dit vlaggetje
    /// zou een mislukte VOD-poging bij elke hernieuwde poging opnieuw diezelfde
    /// melding sturen, net als liveNotified hierboven voorkomt bij LIVE. Optioneel
    /// om dezelfde decode-compatibiliteitsreden.
    var vodNotified: Bool? = nil
    /// nil = .best, for the same decode-compatibility reason as the flags above.
    var quality: VideoQuality? = nil

    var youtubeID: String? { extractYouTubeID(from: url) }

    /// YouTube's predictable thumbnail CDN path — no API call needed, just the video ID.
    var thumbnailURL: URL? {
        guard let id = youtubeID else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
    }
}

/// Shared with MonitorEngine, which needs the same ID (not tied to a MonitoredVideo)
/// to grep leftover files after a false download failure — see reddenNaFout there.
func extractYouTubeID(from url: String) -> String? {
    for pattern in ["[?&]v=([A-Za-z0-9_-]{6,})", "youtu\\.be/([A-Za-z0-9_-]{6,})",
                    "/live/([A-Za-z0-9_-]{6,})"] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
        let range = NSRange(url.startIndex..., in: url)
        if let m = re.firstMatch(in: url, range: range), let r = Range(m.range(at: 1), in: url) {
            return String(url[r])
        }
    }
    return nil
}

/// Compact "in 6d 3h" / "in 2h 14m" / "in 45m" countdown text — used by the status bar's
/// right-click menu, which (unlike SwiftUI's `Text(_:style:.relative)`) is plain AppKit
/// and doesn't update itself, so it's only built fresh each time the menu is opened.
func formattedCountdown(to date: Date) -> String {
    let interval = date.timeIntervalSinceNow
    if interval <= 0 { return "any moment now" }
    let totalMinutes = Int(interval / 60)
    let days = totalMinutes / 1440
    let hours = (totalMinutes % 1440) / 60
    let minutes = totalMinutes % 60
    if days > 0 { return "in \(days)d \(hours)h" }
    if hours > 0 { return "in \(hours)h \(minutes)m" }
    return "in \(minutes)m"
}

/// A YouTube channel Reprise checks daily for newly scheduled premieres — the
/// user's "watch this channel for upcoming stuff" idea (30-09-2026), so they
/// don't have to go find+paste each premiere URL themselves.
struct TrackedChannel: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// Whatever the user entered: a full URL, an @handle, or a bare handle.
    var url: String
    /// Resolved from yt-dlp once the channel's been checked at least once; nil until then.
    var name: String?
    /// Upcoming-video IDs already seen on this channel, so the next check only
    /// surfaces genuinely new ones instead of re-reporting the same premiere
    /// every day until it airs.
    var knownUpcomingIDs: [String] = []
    var lastChecked: Date? = nil
}

/// A premiere found on a tracked channel that isn't in the main list yet — sits
/// here until the user adds it (or dismisses it) from the Discovered section.
struct DiscoveredVideo: Identifiable, Codable, Equatable {
    var id: String { videoID }
    var videoID: String
    var title: String
    var channelName: String
    var channelId: UUID

    var url: String { "https://www.youtube.com/watch?v=\(videoID)" }
}

struct AppSettings: Codable, Equatable {
    /// How many minutes before the scheduled time we start checking.
    var checkLeadMinutes: Double = 15
    /// How often (in minutes) we check once LIVE is already captured and we're waiting for the VOD.
    var vodWaitMinutes: Double = 2
    /// Don't send a failure notification for the same premiere more often than this (in minutes).
    var failureCooldownMinutes: Double = 5
    /// Custom download location; nil = default ~/Downloads/Reprise.
    var customDownloadPath: String? = nil
    /// Pushover credentials, set from within the app's own Settings screen. nil/empty =
    /// push notifications are off; local macOS banners still work regardless.
    var pushoverToken: String? = nil
    var pushoverUserKey: String? = nil
    /// Below this, the disk-space banner/push fires. nil = the 5GB default.
    /// Optional for the same decoding-safety reason as the video flags in
    /// MonitoredVideo above.
    var lowDiskThresholdGB: Double? = nil
    /// Whether Reprise keeps a permanent Dock icon instead of staying menu-bar-only.
    /// nil/false = the original behavior (accessory app, briefly becomes regular only
    /// while a window is open, for keyboard focus — see StatusItemController).
    var showDockIcon: Bool? = nil
    /// Whether the menu bar icon stays neutral (monochrome, blends with the menu bar) when
    /// everything is fine, only turning red/blue for a problem or an active download. nil =
    /// true (the default, added 28-09-2026 — a permanently green icon for "all good" turned
    /// out to be more visual noise than useful signal; color is more meaningful reserved for
    /// the states that actually need attention).
    var minimalMenuBarIcon: Bool? = nil
    /// Which browser yt-dlp reads YouTube login cookies from: "chrome", "safari", or
    /// nil/anything else for automatic (Chrome if present, else Safari). Explicit so a Mac
    /// with both installed but only logged into one doesn't get the wrong one guessed —
    /// auto-detection prefers Chrome unconditionally, which is wrong if you're actually
    /// logged into YouTube in Safari.
    var cookieBrowserPreference: String? = nil
    /// Set to true the first time any video's real format list (checked either
    /// at Look Up or, more often, once a premiere actually goes live/VOD —
    /// see MonitorEngine.hasPremiumFormat) shows YouTube Premium's higher-
    /// bitrate format via the current cookies. Never reset back to false
    /// automatically — there's no reliable negative signal, since "not found
    /// on this video" just as often means this particular video, not a lack
    /// of Premium. Drives whether AddVideoView's quality dropdown offers
    /// "Premium*" at all; once offered it stays offered, since by then every
    /// other video is just as plausible a candidate as the one that proved it.
    var youtubePremiumConfirmed: Bool? = nil
}
