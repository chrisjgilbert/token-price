# Fits generated prose into a character budget without cutting a word in half.
# Both places a "so what" is surfaced need this: the events page renders what
# MarketEvent::Insight persisted, and MarketEvent::Announcement squeezes the
# same text into BlueSky's 300-character post.
module MarketEvent::Prose
  # Whole sentences that fit, else a word-boundary cut with an ellipsis. A raw
  # character cut ends a sentence mid-word ("by a real marg…"), which reads as
  # broken rather than abbreviated.
  def self.fit(text, limit:)
    # Squished first because the sentence scan can't cross a newline: a blurb
    # whose opening line has no terminator would otherwise match no sentence and
    # be dropped from the front. Nothing is lost — the events page renders this
    # in a single <p> and a social post reads better on one line either way.
    text = text.to_s.squish
    return text if text.length <= limit

    kept = +""
    text.scan(/\S.*?[.!?](?=\s|\z)/).each do |sentence|
      candidate = kept.empty? ? sentence : "#{kept} #{sentence}"
      break if candidate.length > limit

      kept = candidate
    end
    kept.presence || text.truncate(limit, separator: /\s/, omission: "…")
  end
end
