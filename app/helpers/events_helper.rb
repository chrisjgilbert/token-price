module EventsHelper
  # Group market events into [year, events] pairs for the events page: newest
  # year first, and within each year newest event first. Order-independent of
  # the input — it sorts both the years and each group itself — so it produces
  # the same display whichever order the page slice arrives in.
  def events_by_year(events)
    events
      .group_by { |e| e.event_date.year }
      .sort_by { |year, _| -year }
      .map { |year, group| [ year, group.sort_by { |e| [ e.event_date, e.title ] }.reverse ] }
  end

  # Freshness timestamp for the homepage, used as its Last-Modified for
  # conditional GET. It spans the price catalog and the model and provider rows
  # the price table renders, plus the market events in the hero card — so an
  # admin edit to any of them revalidates instead of serving a stale 304.
  # A few indexed MAX() aggregates over small tables; no rows are loaded.
  def timeline_last_modified
    [
      PriceCatalog.last_modified,
      MarketEvent.maximum(:updated_at),
      AiModel.maximum(:updated_at),
      Provider.maximum(:updated_at)
    ].compact.max
  end

  # The bare host for a citation chip — "techcrunch.com" reads better than a long
  # title or full URL. The full title rides along as the link's tooltip.
  def citation_host(url)
    URI.parse(url).host&.delete_prefix("www.") || url
  rescue URI::InvalidURIError
    url
  end
end
