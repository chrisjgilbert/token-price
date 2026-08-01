class EventsController < ApplicationController
  # How many timeline entries a page holds. The first page renders with the
  # document; later pages are appended as the sentinel scrolls into view.
  PER_PAGE = 20

  def index
    @page = [ params[:page].to_i, 1 ].max

    # The same URL serves a cumulative HTML page (a direct/no-JS hit) and a Turbo
    # Stream append (the infinite-scroll fetch), chosen by Accept. Vary on it so a
    # shared cache can't hand one representation to a request that wants the other.
    response.headers["Vary"] = [ response.headers["Vary"], "Accept" ].compact.join(", ")

    # Freshness spans more than the timeline's own rows: the shared layout
    # footer counts models and providers, so a MarketEvent-only stamp would
    # serve a stale count after an import — and would be nil entirely on an
    # empty table, leaving the static etag to 304 forever. The page varies by
    # page number and response format (a full HTML page vs. a Turbo Stream
    # append), so both ride the etag — otherwise one view would 304 off the
    # other's cache.
    return if catalog_fresh?(etag: [ :events, @page, request.format.symbol ],
      last_modified: helpers.timeline_last_modified)

    published = MarketEvent.published
    total = published.count

    # The count and earliest year drive the header, which only the full HTML
    # page renders — skip the extra query on the Turbo Stream append path.
    unless request.format.turbo_stream?
      @total_count = total
      @earliest_year = published.minimum(:event_date)&.year
    end

    # The Turbo Stream response appends only the requested page; a direct HTML
    # hit (no JS, or the "Load more" link) renders everything up to and including
    # the requested page so the standalone page stays coherent.
    upper = @page * PER_PAGE
    lower = request.format.turbo_stream? ? (@page - 1) * PER_PAGE : 0
    @events = published.recent_first.offset(lower).limit(upper - lower).to_a
    @has_more = upper < total
    @next_page = @page + 1
    @events_by_year = helpers.events_by_year(@events)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end
end
