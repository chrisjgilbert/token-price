# Fits generated prose into a character budget without cutting a word in half.
# Both places a "so what" is surfaced need this: the events page renders what
# MarketEvent::Insight persisted, and MarketEvent::Announcement squeezes the
# same text into BlueSky's 300-character post.
module MarketEvent::Prose
  # Whole sentences that fit, else a word-boundary cut with an ellipsis. A raw
  # character cut ends a sentence mid-word ("by a real marg…"), which reads as
  # broken rather than abbreviated.
  def self.fit(text, limit:)
    text = text.to_s.strip
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
