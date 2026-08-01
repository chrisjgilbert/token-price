# Posts a published MarketEvent to BlueSky and Mastodon. Reached through
# MarketEvent#announce; never called directly. Idempotent (guards on status +
# announced_at) and non-fatal: a posting failure is logged, not raised, so the
# admin publish action never 500s on a flaky social API.
class MarketEvent::Announcement
  BASE_URL = "https://tokenprice.fyi"
  EVENTS_URL = "#{BASE_URL}/events"
  # Below this, drop the blurb rather than post a stub fragment.
  MIN_BLURB_CHARS = 40

  def initialize(event)
    @event = event
  end

  def run
    return unless announceable?

    SocialBroadcast.post(post_text)

    # A single stamp (not one per platform) is deliberate for v1: it prevents
    # re-posting to the platform that succeeded if the other was flaky. Per-platform
    # tracking is deferred (see SOCIAL_PRESENCE_PLAN.md, P1).
    @event.update_column(:announced_at, Time.current)
  rescue => e
    Rails.logger.error("MarketEvent::Announcement: #{e.class} — #{e.message}")
    Honeybadger.notify(e) if defined?(Honeybadger)
  end

  private

  def announceable?
    @event.status == "published" && @event.announced_at.nil?
  end

  def post_text
    suffix = "\n\n#{EVENTS_URL}"
    budget = SocialBroadcast::CHAR_LIMIT - suffix.length
    # The title identifies the event, so it gets the budget first; the blurb
    # takes what's left. Fitting them separately means a long blurb can't eat
    # into the title, which truncating the joined body used to allow.
    title = @event.title.to_s.truncate(budget, separator: /\s/, omission: "…")
    "#{[ title, blurb_within(budget - title.length - 2) ].compact.join("\n\n")}#{suffix}"
  end

  # The "so what" is the more shareable line, so it leads when present; the note
  # is the fallback for events that haven't been given one yet. Dropped entirely
  # rather than posted as a stub when there's too little room left.
  def blurb_within(budget)
    blurb = (@event.so_what.presence || @event.note).to_s.strip.presence
    return if blurb.nil? || budget < MIN_BLURB_CHARS

    MarketEvent::Prose.fit(blurb, limit: budget)
  end
end
