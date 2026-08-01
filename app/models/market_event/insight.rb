# Generates the "so what" for a MarketEvent — one or two sentences on why the
# event matters for someone pricing or choosing an LLM API — using Claude Sonnet
# 5 with web search, and returns the sources it cited. Reached through
# MarketEvent#generate_insight; returns { so_what:, citations: } or raises Error.
#
# Web search means a forced single-tool call won't do (forcing a custom tool
# blocks the server-side web_search tool), so this goes through
# AnthropicClient.search_call and reads the cited prose back out.
class MarketEvent::Insight
  class Error < StandardError; end

  MODEL      = "claude-sonnet-5"
  MAX_TOKENS = 2048
  # Two sentences carrying real figures ("$14/M blended, $2 in / $12 out, below
  # Sonnet 4.6 at $3/$15") run past 300 on their own — the old 320 cap cut the
  # first sentence of a dense answer in half. The events page wraps freely at
  # 62ch with no clamp, so this is an editorial bound, not a layout one.
  SO_WHAT_LIMIT = 400
  MAX_CITATIONS = 4

  SYSTEM_PROMPT = <<~PROMPT.strip
    You write the "so what" for entries on tokenprice.fyi, a site that tracks LLM API token prices.
    Given a market event, write one or two sentences on why it matters for someone pricing or choosing
    an LLM API — the implication a reader would otherwise have to work out for themselves.

    Use the web search tool to ground the explanation in real sources, and cite them.

    Voice: a developer who tracks this market explaining it to a peer. Describe the implication; don't
    tell the reader what their own situation is. Prefer a concrete figure over a mood. No rhetorical
    questions, no "X is Y" fragments, no hype words. State the consequence plainly.

    Write only the one or two sentences — no preamble, no heading, no "So what:" label.
    Keep the whole thing under #{SO_WHAT_LIMIT} characters.
  PROMPT

  def initialize(event, client: nil)
    @event  = event
    @client = client
  end

  def run
    result = AnthropicClient.search_call(
      model:      MODEL,
      system:     SYSTEM_PROMPT,
      messages:   [ { role: "user", content: prompt } ],
      max_tokens: MAX_TOKENS,
      client:     @client
    )

    {
      so_what:   MarketEvent::Prose.fit(result[:text], limit: SO_WHAT_LIMIT),
      citations: result[:citations].first(MAX_CITATIONS)
    }
  rescue AnthropicClient::Error => e
    raise Error, e.message
  end

  private

  attr_reader :event

  def prompt
    lines = [ "Event: #{event.title}", "Date: #{event.event_date}" ]
    lines << "Detail: #{event.note}"        if event.note.present?
    lines << "Known source: #{event.source_url}" if event.source_url.present?

    items = event.news_items.to_a
    if items.any?
      lines << "Reported by:"
      items.each do |item|
        lines << "  - #{[ item.title, item.source, item.url ].compact_blank.join(' — ')}"
      end
    end

    lines.join("\n")
  end
end
