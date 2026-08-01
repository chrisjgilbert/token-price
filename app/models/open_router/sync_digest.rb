module OpenRouter
  # Presents a ModelSync::Result as the Slack Block Kit payload for the team's
  # #token-price channel — an internal roundup of what the sync repriced and
  # imported, so the new rows can be curated.
  #
  #   payload = OpenRouter::SyncDigest.new(result).to_slack_payload
  #   # => Hash, or nil when nothing changed
  class SyncDigest
    BASE_URL = "https://tokenprice.fyi"

    # Slack rejects a message ("invalid_blocks", HTTP 400) once a message has
    # more than 50 blocks. LINE_PACK_LIMIT (passed to SlackBlockPacker) leaves
    # headroom under Slack's 3000-char section limit for the bold group header
    # (merged into the first chunk) and the "see all" trailer (merged into the
    # last chunk), so neither push a block past the cap.
    LINE_PACK_LIMIT = 2700
    MAX_BLOCKS       = 50

    def initialize(result, date: Date.current)
      @result = result
      @date   = date
    end

    # Returns the Slack payload Hash, or nil if nothing changed.
    def to_slack_payload
      sections = []
      sections.concat(price_moves_section) if @result.repriced_records.any?
      sections.concat(new_models_section)  if @result.created_records.any?
      return nil if sections.empty?

      blocks = [ header_block, *sections ]
      if blocks.size > MAX_BLOCKS
        Rails.logger.warn("OpenRouter::SyncDigest: #{blocks.size} blocks built, " \
                           "truncating to Slack's #{MAX_BLOCKS}-block limit")
        blocks = blocks.first(MAX_BLOCKS)
      end

      { text: "Token Price sync — #{@date.strftime('%-d %b %Y')}", blocks: blocks }
    end

    private

    def header_block
      { type: "header",
        text: { type: "plain_text", text: "Token Price · #{@date.strftime('%-d %b %Y')}" } }
    end

    # Returns one or more mrkdwn section blocks (chunked to stay under Slack's
    # per-block character limit — see LINE_PACK_LIMIT).
    def price_moves_section
      lines   = @result.repriced_records.map { |r| price_move_line(r) }
      header  = "*💰 Price moves (#{lines.size})*"
      trailer = slack_link("#{BASE_URL}/changes", "See all recent price changes →")
      pack_blocks(lines, header: header, trailer: trailer)
    end

    def price_move_line(r)
      model_link = slack_link("#{BASE_URL}/models/#{r.model_slug}", r.model_name)
      edit_link  = slack_link("#{BASE_URL}/admin/models/#{r.model_slug}/edit", "edit")
      pct        = r.pct_input_change
      sign       = pct >= 0 ? "+" : ""
      cached_str = (r.old_cached || r.new_cached) ?
        ", $#{fmt(r.old_cached)}→$#{fmt(r.new_cached)} cached" : ""
      "• #{model_link} (#{r.provider_name}) — " \
        "$#{fmt(r.old_input)}→$#{fmt(r.new_input)} in, " \
        "$#{fmt(r.old_output)}→$#{fmt(r.new_output)} out#{cached_str} · " \
        "#{sign}#{pct}% input · #{edit_link}"
    end

    def new_models_section
      lines  = @result.created_records.map { |r| new_model_line(r) }
      header = "*🆕 New models (#{lines.size})*"
      pack_blocks(lines, header: header)
    end

    def new_model_line(r)
      edit_link    = slack_link("#{BASE_URL}/admin/models/#{r.model_slug}/edit", "edit")
      provider_str = r.new_provider ? "*#{r.provider_name} — new provider ★*" : r.provider_name
      price_str    = "$#{fmt(r.input_per_mtok)}/$#{fmt(r.output_per_mtok)} per MTok"
      "• #{r.model_name} (#{provider_str}) — #{price_str} · #{edit_link}"
    end

    # Packs `lines` into one or more mrkdwn section blocks. `header` is merged
    # into the first block and `trailer` (if given) into the last, so a single
    # line long enough to fill a block on its own can never overflow either.
    def pack_blocks(lines, header:, trailer: nil)
      chunks = SlackBlockPacker.pack(lines, limit: LINE_PACK_LIMIT)
      chunks.each_with_index.map do |chunk, i|
        parts = []
        parts << header if i.zero?
        parts.concat(chunk)
        parts << trailer if trailer && i == chunks.size - 1
        mrkdwn_section(parts.join("\n"))
      end
    end

    def mrkdwn_section(text)
      { type: "section", text: { type: "mrkdwn", text: text } }
    end

    def slack_link(url, text) = "<#{url}|#{text}>"

    def fmt(value)
      return "0" if value.nil? || value.zero?
      # Four decimal places preserves sub-cent prices (e.g. $0.003 cached); strip trailing zeros.
      sprintf("%.4f", value.to_f).sub(/\.?0+$/, "")
    end
  end
end
