namespace :market_events do
  desc "Generate the \"so what\" for published market events missing one or stored mid-sentence"
  task backfill_insights: :environment do
    # The trailing "..." marks a value written by the old raw-character cut in
    # MarketEvent::Insight — regenerating rewrites it under the sentence-aware fit.
    scope = MarketEvent.published
      .where(so_what: [ nil, "" ]).or(MarketEvent.published.where("so_what LIKE ?", "%..."))
      .chronological
    total = scope.count
    puts "Backfilling the \"so what\" for #{total} market event(s)…"

    scope.each.with_index(1) do |event, i|
      event.generate_insight
      puts "  [#{i}/#{total}] #{event.title}"
    rescue MarketEvent::Insight::Error => e
      warn "  [#{i}/#{total}] #{event.title} — skipped: #{e.message}"
    end

    puts "Done."
  end
end
